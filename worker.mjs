// Public-address-only worker. Produces unsigned proofs; never broadcasts.
import {JsonRpcProvider,Contract,keccak256,solidityPackedKeccak256,Interface,getAddress,formatEther} from 'ethers';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {randomBytes} from 'node:crypto';
import {writeFileSync,renameSync} from 'node:fs';
const TOKEN='0x89dfBD9bdd2617141Fe159AB042069814F9B8F6E';
const REGISTRY='0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F';
const HASH='0xa1d44bcfabbef2907ae1743eb6f92bf7734118e422497679100af88d36f08995';
const ABI=['function agentRegistry() view returns(address)','function miningState(address) view returns(uint256 round,bytes32 challenge,uint256 target,uint256 difficulty,uint256 reward,uint256 remaining,uint256 globalMines,bool eligible)','function walletCapacity(address) view returns(uint256)','function isValidSolution(address,uint256,uint256,uint256) view returns(bool)','function mine(uint256,uint256,uint256)'];
const wallet=getAddress(process.argv[2]);
const duration=Number(process.argv[3]||'3300');
if(!Number.isInteger(duration)||duration<1||duration>3600)throw Error('duration must be 1..3600');
const rpc=new JsonRpcProvider('https://bsc-rpc.publicnode.com');
rpc._getConnection().timeout=15000;
const token=new Contract(TOKEN,ABI,rpc);
const save=(name,data)=>{const text=JSON.stringify(data,(_,v)=>typeof v==='bigint'?String(v):v,2);writeFileSync(name+'.tmp',text+'\n');renameSync(name+'.tmp',name);};
const [network,code,registry]=await Promise.all([rpc.getNetwork(),rpc.getCode(TOKEN),token.agentRegistry()]);
if(network.chainId!==56n||keccak256(code)!==HASH||registry.toLowerCase()!==REGISTRY.toLowerCase())throw Error('chain/runtime/registry mismatch');
async function state(){const s=await token.miningState(wallet);if(!s.eligible||!s.remaining)throw Error('ineligible or finished');if(s.globalMines+1n<50000n&&await token.walletCapacity(wallet)<s.reward)throw Error('wallet cap');return s;}
let s=await state();
console.log(JSON.stringify({kind:'preflight',wallet,eligible:s.eligible,difficulty:String(s.difficulty),remaining:String(s.remaining),bnb:formatEther(await rpc.getBalance(wallet))}));
if(process.argv.includes('--check-only'))process.exit(0);
const child=spawn('./keccak-gpu',[],{stdio:['pipe','pipe','inherit']});
const lines=createInterface({input:child.stdout});const iterator=lines[Symbol.asyncIterator]();
let stopping=false;
process.on('SIGTERM',()=>{stopping=true;child.kill();});process.on('SIGINT',()=>{stopping=true;child.kill();});
async function scan(task,np,start,count,target=task.target){
 child.stdin.write(`${task.challenge.slice(2)}${wallet.slice(2).toLowerCase()} ${np} ${target.toString(16).padStart(64,'0')} ${start} ${count}\n`);
 const {value,done}=await iterator.next();if(done)throw Error('GPU process ended');
 const r=JSON.parse(value);if(BigInt(r.hashes)!==count||!(r.seconds>0))throw Error('invalid GPU batch result');
 if(r.found){const ctr=BigInt(r.counter);if(ctr<start||ctr>=start+count)throw Error('counter outside batch');const nonce=BigInt('0x'+np+ctr.toString(16).padStart(16,'0'));const proof=solidityPackedKeccak256(['bytes32','address','uint256'],[task.challenge,wallet,nonce]);if(BigInt(proof)>=target)throw Error('GPU result does not match independent ethers hash');r.nonce=nonce;r.proof=proof;}
 return r;
}
try {
 // Force real GPU search to return a result at a 64-bit nonce boundary;
 // verify it independently before allowing real work.
 for(const start of [0n,4294967294n,18446744073709551000n]){
  const r=await scan(s,randomBytes(24).toString('hex'),start,256n,(1n<<256n)-1n);if(!r.found)throw Error('GPU search self-test failed');
 }
 console.log(JSON.stringify({kind:'gpu-search-selftest',passed:true,cases:3}));
 const began=Date.now(),deadline=began+duration*1000;let hashes=0n,count=1n<<20n,counter=0n,lastLog=0;
 const np=randomBytes(24).toString('hex');
 while(!stopping&&Date.now()<deadline){
  s=await state();const r=await scan(s,np,counter,count);counter+=count;hashes+=count;
  const hps=Number(count)/r.seconds;
  count=BigInt(Math.min(2**29,Math.max(2**20,Math.floor(hps))));
  if(r.found){
   const current=await state();
   if(current.round!==s.round||current.challenge!==s.challenge)continue;
   const ref=BigInt(r.proof)<current.target?current.globalMines:s.globalMines;
   if(!await token.isValidSolution(wallet,s.round,r.nonce,ref))continue;
   const candidate={kind:'unsigned-pow-candidate',chainId:56,from:wallet,to:TOKEN,value:'0',personalRound:s.round,nonce:r.nonce,referenceEpoch:ref,challenge:s.challenge,proof:r.proof,data:new Interface(ABI).encodeFunctionData('mine',[s.round,r.nonce,ref]),foundAt:new Date().toISOString(),transactionsSent:0};
   save('candidate.json',candidate);console.log(JSON.stringify(candidate,(_,v)=>typeof v==='bigint'?String(v):v));break;
  }
  if(Date.now()-lastLog>5000){
   const status={kind:'mining',at:new Date().toISOString(),elapsedSeconds:Math.round((Date.now()-began)/1000),hashes,hps:Math.round(hps),difficulty:s.difficulty,expectedSecondsAtCurrentRate:Number(s.difficulty)/hps,personalRound:s.round,globalMines:s.globalMines,transactionsSent:0};save('status.json',status);console.log(JSON.stringify(status,(_,v)=>typeof v==='bigint'?String(v):v));lastLog=Date.now();
  }
 }
 console.log(JSON.stringify({kind:'stopped',hashes:String(hashes),transactionsSent:0}));
}finally{child.stdin.end();child.kill();}

import {randomBytes} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {keccak256,solidityPackedKeccak256} from 'ethers';
const vectors=[Buffer.alloc(84),Buffer.alloc(84,255),...Array.from({length:254},()=>randomBytes(84))];
const p=spawnSync(process.argv[2]||'./keccak-cpu',['--vectors'],{input:vectors.map(b=>b.toString('hex')).join('\n')+'\n',encoding:'utf8'});
if(p.status!==0)throw Error(p.stderr||'vector process failed');
const hashes=p.stdout.trim().split('\n');
if(hashes.length!==vectors.length)throw Error('wrong vector count');
for(let i=0;i<vectors.length;i++) {
 const b=vectors[i];
 const packed=solidityPackedKeccak256(['bytes32','address','uint256'],['0x'+b.subarray(0,32).toString('hex'),'0x'+b.subarray(32,52).toString('hex'),BigInt('0x'+b.subarray(52).toString('hex'))]);
 if('0x'+hashes[i]!==keccak256(b)||'0x'+hashes[i]!==packed)throw Error('mismatch at '+i);
}
console.log(JSON.stringify({test:'Keccak-256 / 84-byte ABI packed',vectors:vectors.length,passed:true,binary:process.argv[2]}));

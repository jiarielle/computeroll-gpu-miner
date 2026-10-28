# ComputeRoll CUDA worker

CUDA Keccak-256 worker for RTX 4090 (`sm_89`) and RTX 5090 (`sm_120`), producing unsigned proof
candidates only. It never signs or broadcasts a blockchain transaction.

The image contains no wallet address, wallet session or API credentials.
Configure a public eligible BSC address at runtime with `CROLL_WALLET`.
`CROLL_SECONDS` must be 1–3600 (default 3600).

```
docker run --rm --gpus all \
  -e CROLL_WALLET=YOUR_PUBLIC_BSC_ADDRESS \
  -e CROLL_SECONDS=3600 \
  ghcr.io/jiarielle/computeroll-gpu-miner:v0.2.1
```

Use the immutable digest from the build summary for deployment. The startup
script runs 256 GPU hash vectors against ethers before real work. The worker
then runs three CUDA search boundary tests, checks the chain and contract
runtime, and reads eligibility and capacity for the exact submitting address.

## Protocol

- Network: BNB Smart Chain, chain ID 56.
- Contract: `0x89dfBD9bdd2617141Fe159AB042069814F9B8F6E`.
- Runtime hash: `0xa1d44bcfabbef2907ae1743eb6f92bf7734118e422497679100af88d36f08995`.
- Hash: legacy Keccak-256 of `bytes32 challenge || address miner || uint256 nonce`
  (84 bytes, nonce in big-endian form). This is not NIST SHA3-256.

The worker stops after the first validated candidate or timeout. The candidate
is saved to `candidate.json` and printed to standard output. A candidate is not
a token reward and may expire; independently revalidate it and review any
wallet transaction before submission. No approvals or deposits are needed by
this worker.

Build checks compile the CUDA kernel and test the container's CPU runtime.
They do not run mining on GitHub Actions. GPU validation must occur on your
own authorized GPU instance. The same hash core was tested on an RTX 4090
against 256 ethers vectors and three actual search boundary cases. RTX 5090 CUDA kernels are included; an actual 5090 GPU validation is still required.

For Salad, use one replica, disable autostart and automatic restart, omit
public networking, and arrange a separate API stop watchdog before starting.
A process timeout alone does not guarantee cloud billing stops. Expect nodes
to disappear and keep blockchain signing credentials off the GPU host.

Dependencies: ethers 6.17.0; Node.js 22; CUDA 12.8.1. Build with:

```
npm ci --ignore-scripts
docker build --platform linux/amd64 -f Dockerfile.salad -t computeroll-gpu-miner .
```

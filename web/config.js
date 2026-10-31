// Burrow v2 on Sepolia (deployed 2026-10-31). Addresses also live in ../burrow_deployed.json.
export const CONFIG = {
  chainId: 11155111,
  chainHex: '0xaa36a7',
  rpcs: ['https://ethereum-sepolia-rpc.publicnode.com', 'https://sepolia.gateway.tenderly.co'],   // rpc.sepolia.org has no CORS
  squeekchain: {
    sqk: '0x5501e1fa81be1c3f49225fa7668da0245d07db60',
    nft: '0xcb98349c134ab983da5bfd80527dfe2552bdb70f',
    staking: '0x4b67b739dfd832f4eac67a7aa3bc244fb74cea4f',
    mining: '0xcd46990f8349057335289ef282c276204b6cdc62',
    api: 'https://api.squeekchain.com/v1',
    nftBlock: 11700000,   // before the Squeek genesis; Transfer scans start here (public RPCs keep no archive state for getCode bisection)
  },
  burrow: {
    vault:  '0xB63AbAb9019fa0Db4A3Ab1824C5E5Fa7171f1472',  // bSQK
    valuer: '0x8F677a270fFd8769C01876216991c98561302C7b',
    market: '0xDF0b997E701AaB73e69417e1910a9a9D93F0De8d',
    hook:   '0x9e0827db5831c49F9390707b467aA12A76E74044',  // low 14 bits 0x44
    vaultBlock: 12033611,
  },
  explorer: 'https://sepolia.etherscan.io',
};

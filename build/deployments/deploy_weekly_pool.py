
from build.deployments.deploy_utils import setup_mainnet_accounts

Accs = setup_mainnet_accounts()

frontend_pool_str = """
  {{
    sousId: ??,
    tokenName: '??',
    tokenPoolAddress: '0xED0B4b0F0E2c17646682fc98ACe09feB99aF3adE',
    quoteTokenSymbol: QuoteToken.RVRS,
    quoteTokenPoolAddress: '0xED0B4b0F0E2c17646682fc98ACe09feB99aF3adE',
    stakingTokenName: QuoteToken.??,
    stakingTokenAddress: '{want_address}',
    contractAddress: {{
      1666700000: '{contract_address}',
      1666600000: '{contract_address}',
    }},
    poolCategory: PoolCategory.CORE,
    projectLink: '',
    harvest: true,
    sortOrder: 1,
    tokenDecimals: 18,
    isFinished: false,
    isDepositFinished: false,
    tokenPerBlock: '{rew_per_block}',
    startBlock: {start_block},
    endBlock: {end_block},
    lockBlock: {end_block},
  }},
"""

LP_UST_RVRS = "0xF8838fcC026d8e1F40207AcF5ec1DA0341c37fe2"
LP_RVRS_ONE = "0xCDe0A00302CF22B3Ac367201FBD114cEFA1729b4"
LP_ETH_RVRS = "0xd1af43eb1d14b0377fbe35d2Bfadab16b96c0911"
LP_USDC_RVRS = "0x15B78BEcF030cB136C1dB53b79408BF0483dc1E8"
UST = "0x224e64ec1BDce3870a6a6c777eDd450454068FEC"
RVRS = "0xED0B4b0F0E2c17646682fc98ACe09feB99aF3adE"
JEWEL = "0x72Cb10C6bfA5624dD07Ef608027E366bd690048F"

multisig = "0xA3904e99b6012EB883DB1090D02D4e954539EC61"

rvrs = Contract.from_abi("ReverseToken", RVRS, abi=ReverseToken.abi)


####################################
n_days = 5
hour_offset = 0.7
start_block = int(chain.height + 30*60*hour_offset)
lock_block = int(start_block + 30*60*24*n_days)
end_block = lock_block + 1

wantAddress = UST
burnRate = 0
rew_per_block = 43000000000000000

print(f"Deploying bond pool for\n"
      f" want:\tUST ({wantAddress})\n"
      f" burn:\t{burnRate/100:.2f}%\n"
      f" rew:\t{rew_per_block/1e18:.3f} / block\n"
      f" start:\t{start_block}\n"
      f" end:\t{end_block}")


bond_pool = BondingPool.deploy(
    wantAddress,
    rvrs,
    rew_per_block,
    start_block,
    lock_block,
    end_block,
    multisig,
    burnRate,
    {'from': Accs.deployer}
)

print(f"WARNING: PLEASE SEND {(end_block-start_block)*rew_per_block/1e18:.2f} RVRS to {bond_pool.address}\n")

print(frontend_pool_str.format(
    want_address=wantAddress,
    contract_address=bond_pool.address,
    rew_per_block=str(rew_per_block/1e18)[:5],
    start_block=start_block,
    end_block=end_block,
))


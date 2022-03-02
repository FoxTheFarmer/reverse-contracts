"""
ReverseToken:
Reverseum:
Masterchef:
Vault:

Pools:
0: 50, RVRS - 0xED0B4b0F0E2c17646682fc98ACe09feB99aF3adE
1: 35, RVRS/ONE - 0xCDe0A00302CF22B3Ac367201FBD114cEFA1729b4
2: 00, ONE/UST - 0x61356C852632813f3d71D57559B06cdFf70E538B
3: 05, RVRS/UST - 0xF8838fcC026d8e1F40207AcF5ec1DA0341c37fe2

FOX/RVRS - 0xe52e3f81b0D21E42Ab33E5a7dad908713f48621f
MIS/RVRS - 0x14eC453656Ce925C969eafFcD76d62ACA2468Eb6

BondPool - UST/RVRS - 0x37B380C2593a172e92a5f0BbAcA3BCfc9091060B
"""

import time
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
    tokenPerBlock: '{rew_per_block}',
    sortOrder: 1,
    isFinished: false,
    isDepositFinished: false,
    startBlock: {start_block},
    endBlock: {end_block},
    lockBlock: {end_block},
    tokenDecimals: 18,
  }},
"""


LP_UST_RVRS = "0xF8838fcC026d8e1F40207AcF5ec1DA0341c37fe2"
LP_RVRS_ONE = "0xCDe0A00302CF22B3Ac367201FBD114cEFA1729b4"
LP_ETH_RVRS = "0xd1af43eb1d14b0377fbe35d2Bfadab16b96c0911"
LP_USDC_RVRS = "0x15B78BEcF030cB136C1dB53b79408BF0483dc1E8"
UST = "0x224e64ec1BDce3870a6a6c777eDd450454068FEC"
RVRS = "0xED0B4b0F0E2c17646682fc98ACe09feB99aF3adE"

multisig = "0xA3904e99b6012EB883DB1090D02D4e954539EC61"
token = "0xED0B4b0F0E2c17646682fc98ACe09feB99aF3adE"
treasury = "0x3153A73841844953ea3BE0Da05029C18E30e3392"
masterchef = "0xeEA71889c062c135014Ec34825a1958c87A2Ac61"
auto_rvrs = "0xC9ED8bfb89F5B5ca965AA8cEAacF75576C06211E"
auto_rvrs2 = "0x0b075c7F350E0E844d76dFDe4D4c816a365dC879"
# admin = Accs.deployer


rvrs = Contract.from_abi("ReverseToken", token, abi=ReverseToken.abi)
reverseum = Contract.from_abi("Reverseum", treasury, abi=Reverseum.abi)
chef = Contract.from_abi("CoffinMakerV2", masterchef, abi=CoffinMakerV2.abi)
vault = Contract.from_abi("AutoRvrs", auto_rvrs, abi=AutoRvrs.abi)
vault2= Contract.from_abi("AutoRvrs", auto_rvrs2, abi=AutoRvrs.abi)


# Update pools
chef.setPool(0, 100, 0, 0, 0, True, {'from': Accs.deployer})
chef.setPool(1, 0, 0, 0, 0, True, {'from': Accs.deployer})
chef.setPool(3, 0, 0, 0, 0, True, {'from': Accs.deployer})

print(chef.poolInfo(0))
print(chef.poolInfo(1))
print(chef.poolInfo(2))
print(chef.poolInfo(3))

# ust_bond = Contract.from_abi("BondingPool", '', abi=BondingPool.abi)
# lp_bond = Contract.from_abi("BondingPool", '', abi=BondingPool.abi)

# resp = rvrs.mint(Accs.deployer, int(INITIAL_MINT_AMOUNT*1e18), {'from': Accs.deployer})

# Reverseum
# reverseum = Reverseum.deploy({'from': Accs.deployer})

# Masterchef
# chef = CoffinMakerV2.deploy({'from': Accs.deployer})
# resp = chef.init(
#     rvrs,
#     1636844400,
#     400000000000000000,
#     reverseum,
#     {'from': Accs.deployer}
# )

# resp = reverseum.setGate(chef, {'from': Accs.deployer})
# resp = chef.setDevFund(Accs.deployer, {'from': Accs.deployer})
# resp = chef.setMarketingFund(Accs.deployer, {'from': Accs.deployer})
# resp = chef.setProfitSharingFund(multisig, {'from': Accs.deployer})
#
# resp = chef.addPool(50, rvrs, 0, 0, 0, False)
# resp = chef.addPool(35, '0xCDe0A00302CF22B3Ac367201FBD114cEFA1729b4', 0, 0, 0, False)
# resp = chef.addPool(0, '0x61356C852632813f3d71D57559B06cdFf70E538B', 0, 0, 0, False)
# resp = chef.addPool(5, '0xF8838fcC026d8e1F40207AcF5ec1DA0341c37fe2', 0, 0, 0, False)
#
# resp = rvrs.transferOwnership(chef, {'from': Accs.deployer})

vault = AutoRvrs.deploy(rvrs, chef, admin, multisig, {'from': Accs.deployer})
vault2 = AutoRvrs.deploy(rvrs, chef, admin, multisig, {'from': Accs.deployer})


# Bond pools

# UST
# RVRS/ONE


wantAddress = UST
burnRate = 0
rew_per_block = 300000000000000000
start_block = 19401555
lock_block = 20004470
end_block = 20004471

ust_bond = BondingPool.deploy(
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

ust = interface.ERC20(UST)


wantAddress = LP_RVRS_ONE
burnRate = 5000
rew_per_block = 600000000000000000
start_block = 19401555
lock_block = 20004470
end_block = 20004471

BondingPool.deploy(
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


# Bond Pool UST/RVRS

wantAddress = LP_UST_RVRS
burnRate = 5000  # 50%
rew_per_block = 1120000000000000000  # 1/block
start_block = 19462293
lock_block = 19759996
end_block = 19759997

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

lp_token = interface.ERC20(wantAddress)
lp_token.approve(bond_pool, int(1e33), {'from': Accs.dev})
dev_bal = lp_token.balanceOf(Accs.dev)
print(f"Dev balance = {dev_bal}")

resp = bond_pool.transact(dev_bal, {'from': Accs.dev})

###################################
#

wantAddress = LP_UST_RVRS
burnRate = 5000  # 50%
rew_per_block = 1000000000000000000  # 1/block
n_days = 5

start_block = int(time.time() + 5400)  # 3 hour offset
lock_block = int(start_block + 30*60*24*n_days)
end_block = lock_block + 1

print(f"Deploying bond pool for\n"
      f" want:\t{wantAddress}"
      f" burn:\t{burnRate/100:.2f}%\n"
      f" rew:\t{rew_per_block/1e18:.3f}\n"
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


################################
hour_offset = 4  # 4 hour offset
start_block = int(chain.height + 30*60*hour_offset)
lock_block = int(start_block + 30*60*24*n_days)
end_block = lock_block + 1


wantAddress = LP_ETH_RVRS
burnRate = 5000  # 50%
rew_per_block = 1200000000000000000  # 1/block
n_days = 5


print(f"Deploying bond pool for\n"
      f" want:\t{wantAddress}\n"
      f" burn:\t{burnRate/100:.2f}%\n"
      f" rew:\t{rew_per_block/1e18:.3f}\n"
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
    rew_per_block=str(rew_per_block/1e18)[:4],
    start_block=start_block,
    end_block=end_block,
))

lp_token = interface.ERC20(wantAddress)
lp_token.approve(bond_pool, int(1e33), {'from': Accs.dev})
dev_bal = lp_token.balanceOf(Accs.dev)
print(f"Dev balance = {dev_bal}")

resp = bond_pool.transact(dev_bal, {'from': Accs.dev})


####################################
# Nov 24, 2021

# WARNING: PLEASE SEND 432002.00 RVRS to 0x3987CdF7B31b09d7338A00B4b7eB4f4586de02F8
# WARNING: PLEASE SEND 324001.50 RVRS to 0xB654182a34da753fA7E619F45FCE9C4e7338757a
# WARNING: PLEASE SEND 324001.50 RVRS to 0xE78DE8375DCAcbf00426d51373936458198f470d

n_days = 5
hour_offset = 4  # 4 hour offset
start_block = int(chain.height + 30*60*hour_offset)
lock_block = int(start_block + 30*60*24*n_days)
end_block = lock_block + 1
n_days = 5

wantAddress = LP_UST_RVRS
burnRate = 5000  # 50%
rew_per_block = 2000000000000000000  # 1/block

print(f"Deploying bond pool for\n"
      f" want:\t{wantAddress}\n"
      f" burn:\t{burnRate/100:.2f}%\n"
      f" rew:\t{rew_per_block/1e18:.3f}\n"
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
    rew_per_block=str(rew_per_block/1e18)[:4],
    start_block=start_block,
    end_block=end_block,
))

lp_token = interface.ERC20(wantAddress)
lp_token.approve(bond_pool, int(1e33), {'from': Accs.dev})
dev_bal = lp_token.balanceOf(Accs.dev)
print(f"Dev balance = {dev_bal}")

resp = bond_pool.transact(dev_bal, Accs.dev, {'from': Accs.dev})


# USDC/RVRS

wantAddress = LP_USDC_RVRS
burnRate = 5000  # 50%
rew_per_block = 1500000000000000000  # 1/block

print(f"Deploying bond pool for\n"
      f" want:\t{wantAddress}\n"
      f" burn:\t{burnRate/100:.2f}%\n"
      f" rew:\t{rew_per_block/1e18:.3f}\n"
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
    rew_per_block=str(rew_per_block/1e18)[:4],
    start_block=start_block,
    end_block=end_block,
))

lp_token = interface.ERC20(wantAddress)
lp_token.approve(bond_pool, int(1e33), {'from': Accs.dev})
dev_bal = lp_token.balanceOf(Accs.dev)
print(f"Dev balance = {dev_bal}")

resp = bond_pool.transact(dev_bal, Accs.dev, {'from': Accs.dev})


# UST pool
wantAddress = UST
burnRate = 0
rew_per_block = 1500000000000000000  # 1/block

print(f"Deploying bond pool for\n"
      f" want:\t{wantAddress}\n"
      f" burn:\t{burnRate/100:.2f}%\n"
      f" rew:\t{rew_per_block/1e18:.3f}\n"
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
    rew_per_block=str(rew_per_block/1e18)[:4],
    start_block=start_block,
    end_block=end_block,
))

lp_token = interface.ERC20(wantAddress)
lp_token.approve(bond_pool, int(1e33), {'from': Accs.dev})
dev_bal = lp_token.balanceOf(Accs.dev)
print(f"Dev balance = {dev_bal}")

resp = bond_pool.transact(dev_bal, Accs.dev, {'from': Accs.dev})


blocks_left = start_block - chain.height
print(f"\nBlocks Remaining: {blocks_left} ({blocks_left/30/60:.2f} hours)")



####################################
# Dec 13, 2021

n_days = 5
hour_offset = 2  # 4 hour offset
start_block = int(chain.height + 30*60*hour_offset)
lock_block = int(start_block + 30*60*24*n_days)
end_block = lock_block + 1

wantAddress = LP_UST_RVRS
burnRate = 5000  # 50%
rew_per_block = 1120000000000000000

print(f"Deploying bond pool for\n"
      f" want:\t{wantAddress}\n"
      f" burn:\t{burnRate/100:.2f}%\n"
      f" rew:\t{rew_per_block/1e18:.3f}\n"
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
    rew_per_block=str(rew_per_block/1e18)[:4],
    start_block=start_block,
    end_block=end_block,
))

lp_token = interface.ERC20(wantAddress)
lp_token.approve(bond_pool, int(1e33), {'from': Accs.dev})
dev_bal = lp_token.balanceOf(Accs.dev)
print(f"Dev balance = {dev_bal}")

resp = bond_pool.transact(dev_bal, Accs.dev, {'from': Accs.dev})



####################################
# Dec 20, 2021

n_days = 5
hour_offset = 2
start_block = int(chain.height + 30*60*hour_offset)
lock_block = int(start_block + 30*60*24*n_days)
end_block = lock_block + 1

wantAddress = UST
burnRate = 0
rew_per_block = 600000000000000000

print(f"Deploying bond pool for\n"
      f" want:\t{wantAddress}\n"
      f" burn:\t{burnRate/100:.2f}%\n"
      f" rew:\t{rew_per_block/1e18:.3f}\n"
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
    rew_per_block=str(rew_per_block/1e18)[:4],
    start_block=start_block,
    end_block=end_block,
))

lp_token = interface.ERC20(wantAddress)
lp_token.approve(bond_pool, int(1e33), {'from': Accs.dev})
dev_bal = lp_token.balanceOf(Accs.dev)
print(f"Dev balance = {dev_bal}")

resp = bond_pool.transact(dev_bal, Accs.dev, {'from': Accs.dev})



####################################
# Dec 27, 2021

n_days = 5
hour_offset = 2
start_block = int(chain.height + 30*60*hour_offset)
lock_block = int(start_block + 30*60*24*n_days)
end_block = lock_block + 1

wantAddress = UST
burnRate = 0
rew_per_block = 900000000000000000

print(f"Deploying bond pool for\n"
      f" want:\t{wantAddress}\n"
      f" burn:\t{burnRate/100:.2f}%\n"
      f" rew:\t{rew_per_block/1e18:.3f}\n"
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
    rew_per_block=str(rew_per_block/1e18)[:4],
    start_block=start_block,
    end_block=end_block,
))

lp_token = interface.ERC20(wantAddress)
lp_token.approve(bond_pool, int(1e33), {'from': Accs.dev})
dev_bal = lp_token.balanceOf(Accs.dev)
print(f"Dev balance = {dev_bal}")

resp = bond_pool.transact(dev_bal, Accs.dev, {'from': Accs.dev})

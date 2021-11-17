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


from build.deployments.deploy_utils import setup_mainnet_accounts

Accs = setup_mainnet_accounts()


LP_UST_RVRS = "0xF8838fcC026d8e1F40207AcF5ec1DA0341c37fe2"
LP_RVRS_ONE = "0xCDe0A00302CF22B3Ac367201FBD114cEFA1729b4"
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
rew_per_block = 1000000000000000000  # 1/block
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


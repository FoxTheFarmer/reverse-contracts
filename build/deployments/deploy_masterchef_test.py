"""
Test ReverseToken: 0x5A24E33c1F3AC55B96F818D40d0ad97F71b42658
Test Reverseum: 0xB6901a6A14417B0DaA37380770BF0C9bd16EfD5D
Test Masterchef: 0xa385399B4dE3B5f01a31b0E753f32E18e526db8f
Test Vault: 0x9a50FBc4914D920Dc54aF3B4AD4Ee38F7F72b9Ae

Pools:
0: 40%, RVRS - 0x5A24E33c1F3AC55B96F818D40d0ad97F71b42658
1: 50%, RVRS/ONE - 0x006d392b015d154f6580f68d659f803f0d22bcee
2: 00%, ONE/UST - 0x61356C852632813f3d71D57559B06cdFf70E538B
3: 10%, RVRS/UST - 0x513568f49e384811d7cf7e6de4daa4ddc3c4a779

"""

from build.deployments.deploy_utils import setup_mainnet_accounts

Accs = setup_mainnet_accounts()

INITIAL_MINT_AMOUNT = 10000000000

rvrs = ReverseToken.deploy({'from': Accs.deployer})

resp = rvrs.mint(Accs.deployer, int(INITIAL_MINT_AMOUNT*1e18), {'from': Accs.deployer})

# Reverseum
reverseum = Reverseum.deploy({'from': Accs.deployer})

# Masterchef
chef = CoffinMakerV2.deploy({'from': Accs.deployer})
resp = chef.init(
    rvrs,
    chain.time()+60,
    1500000000000000000,
    reverseum,
    {'from': Accs.deployer}
)

resp = reverseum.setGate(chef, {'from': Accs.deployer})
resp = chef.setDevFund(Accs.deployer, {'from': Accs.deployer})
resp = chef.setMarketingFund(Accs.deployer, {'from': Accs.deployer})
resp = chef.setProfitSharingFund(Accs.deployer, {'from': Accs.deployer})

resp = chef.addPool(40, '0x5A24E33c1F3AC55B96F818D40d0ad97F71b42658', 0, 0, 0, False)
resp = chef.addPool(50, '0x006d392b015d154f6580f68d659f803f0d22bcee', 0, 0, 0, False)
resp = chef.addPool(0, '0x61356C852632813f3d71D57559B06cdFf70E538B', 0, 0, 0, False)
resp = chef.addPool(10, '0x513568f49e384811d7cf7e6de4daa4ddc3c4a779', 0, 0, 0, False)

resp = rvrs.transferOwnership(chef, {'from': Accs.deployer})


token = "0x5A24E33c1F3AC55B96F818D40d0ad97F71b42658"
masterchef = "0xa385399B4dE3B5f01a31b0E753f32E18e526db8f"
admin = Accs.deployer
treasury = "0xB6901a6A14417B0DaA37380770BF0C9bd16EfD5D"

vault = AutoRvrs.deploy(token, masterchef, admin, treasury, {'from': Accs.deployer})


# Bond pools

# UST
# RVRS/ONE

LP_RVRS_ONE = "0x006d392b015d154f6580f68d659f803f0d22bcee"
UST = "0x224e64ec1BDce3870a6a6c777eDd450454068FEC"

wantAddress = UST
burnRate = 0

ust_bond = BondingPool.deploy(
    wantAddress,
    rvrs,
    100000000000000000,
    chain.height,
    int(chain.height + 30*60*23),
    int(chain.height + 30*60*24),
    reverseum,
    burnRate,
    {'from': Accs.deployer}
)

ust = interface.ERC20(UST)




wantAddress = LP_RVRS_ONE
burnRate = 6000

lp_bond = BondingPool.deploy(
    wantAddress,
    rvrs,
    100000000000000000,
    chain.height,
    int(chain.height + 30*60*23),
    int(chain.height + 30*60*24),
    reverseum,
    burnRate,
    {'from': Accs.deployer}
)

# TODO - SEND RVRS TO THE FKING CONTRACTS





chef = Contract.from_abi("CoffinMakerV2", '0xa385399B4dE3B5f01a31b0E753f32E18e526db8f', abi=CoffinMakerV2.abi)
reverseum = Contract.from_abi("Reverseum", '0xB6901a6A14417B0DaA37380770BF0C9bd16EfD5D', abi=Reverseum.abi)
vault = Contract.from_abi("AutoRvrs", '0x9a50FBc4914D920Dc54aF3B4AD4Ee38F7F72b9Ae', abi=AutoRvrs.abi)
rvrs = Contract.from_abi("ReverseToken", '0x5A24E33c1F3AC55B96F818D40d0ad97F71b42658', abi=ReverseToken.abi)
ust_bond = Contract.from_abi("BondingPool", '0xb4b35A9bA3cef0565A0039392f9c58982E9aA573', abi=BondingPool.abi)
lp_bond = Contract.from_abi("BondingPool", '0x7429FF70159be178c8a92bEd81068BcB2a6d0686', abi=BondingPool.abi)

"""

"""

from build.deployments.deploy_utils import *
# Accs = setup_mainnet_accounts()


def _from(acc_id):
    return {'from': accounts[acc_id]}

reverseum = accounts[9]
rvrs = ReverseToken.deploy(_from(0))
dummy_token = veRvrsRewards.deploy(_from(0))

rvrs.mint(accounts[1], 1e20)
rvrs.mint(accounts[2], 1e20)
rvrs.mint(accounts[3], 1e20)
rvrs.mint(accounts[4], 1e20)
dummy_token.mint(accounts[0], 1)

# Masterchef
chef = CoffinMakerV2.deploy(_from(0))
resp = chef.init(
    rvrs,
    chain.time()+5,
    300000000000000000,
    reverseum,
    _from(0)
)

# Masterchef setup
resp = chef.setDevFund(reverseum, _from(0))
resp = chef.setMarketingFund(reverseum, _from(0))
resp = chef.setProfitSharingFund(reverseum, _from(0))

resp = chef.addPool(10, rvrs, 0, 0, 0, False)
resp = chef.addPool(0, dummy_token, 0, 0, 0, False)
resp = rvrs.transferOwnership(chef, _from(0))

ve_rvrs = VeRvrs.deploy(_from(0))
ve_rvrs.initialize(rvrs, chef, reverseum, 1, _from(0))

# Approve rvrs for veRvrs
rvrs.approve(ve_rvrs, 1e33, _from(1))
rvrs.approve(ve_rvrs, 1e33, _from(2))
rvrs.approve(ve_rvrs, 1e33, _from(3))
rvrs.approve(ve_rvrs, 1e33, _from(4))

# Deposit
ve_rvrs.deposit(1e18, _from(1))
ve_rvrs.deposit(1e18, _from(2))

# Check veRVRS balances - should be 0.5% of deposit
assert ve_rvrs.balanceOf(accounts[1]) == 5e15, "Bad veRVRS balance"
assert ve_rvrs.balanceOf(accounts[2]) == 5e15, "Bad veRVRS balance"

# TODO tests
# check max cap after time elapses (set time to max cap to like 1 minute)
# test reward breakdowns on claim with multiple users
# test withdraw fee applies and send to rvrsDAO
# test partial withdrawing slashes all veRVRS
# test deposit and claim DON'T reset initial deposit time

# TODO - add a pendingRewards function to contract

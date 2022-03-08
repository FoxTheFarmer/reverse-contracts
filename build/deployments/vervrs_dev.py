
import time

# from build.deployments.deploy_utils import *
# Accs = setup_mainnet_accounts()


def _from(acc_id):
    return {'from': accounts[acc_id]}

reverseum = Reverseum.deploy(_from(0))
rvrsDAO = accounts[8]
rvrs = ReverseToken.deploy(_from(0))
dummy_token = veRvrsRewards.deploy(_from(0))

rvrs.mint(accounts[1], 1e21)
rvrs.mint(accounts[2], 1e21)
rvrs.mint(accounts[3], 1e21)
rvrs.mint(accounts[4], 1e21)
dummy_token.mint(accounts[0], 1)

# Masterchef
chef = CoffinMakerV2.deploy(_from(0))
resp = chef.init(
    rvrs,
    chain.time()+5,
    30000000000000000,
    reverseum,
    _from(0)
)
resp = reverseum.setGate(chef, _from(0))

# Masterchef setup
resp = chef.setDevFund(reverseum, _from(0))
resp = chef.setMarketingFund(reverseum, _from(0))
resp = chef.setProfitSharingFund(reverseum, _from(0))

resp = chef.addPool(10, rvrs, 0, 0, 0, False)
resp = chef.addPool(0, dummy_token, 0, 0, 0, False)
resp = rvrs.transferOwnership(chef, _from(0))

ve_rvrs = VeRvrs.deploy(_from(0))
ve_rvrs.initialize(rvrs, chef, rvrsDAO, 1, _from(0))

# Approve rvrs for veRvrs
rvrs.approve(ve_rvrs, 1e33, _from(1))
rvrs.approve(ve_rvrs, 1e33, _from(2))
rvrs.approve(ve_rvrs, 1e33, _from(3))
rvrs.approve(ve_rvrs, 1e33, _from(4))

# Deposit
ve_rvrs.deposit(1e20, _from(1))
time.sleep(2)
ve_rvrs.deposit(1e20, _from(2))
time.sleep(2)
ve_rvrs.deposit(1e20, _from(3))

# Check veRVRS balances - should be 0.5% of deposit
assert ve_rvrs.totalStaked() == 3e20, "Bad total staked"
assert rvrs.balanceOf(ve_rvrs) == 3e20, "Bad total staked"
assert ve_rvrs.balanceOf(accounts[1]) == 5e17, "Bad veRVRS balance 1"
assert ve_rvrs.balanceOf(accounts[2]) == 5e17, "Bad veRVRS balance 2"
assert ve_rvrs.balanceOf(accounts[3]) == 5e17, "Bad veRVRS balance 3"

assert ve_rvrs.userInfo(accounts[1])[0] == 1e20, "Bad user balance 1"
assert ve_rvrs.userInfo(accounts[2])[0] == 1e20, "Bad user balance 2"
assert ve_rvrs.userInfo(accounts[3])[0] == 1e20, "Bad user balance 3"

# Should revert before we start rewards
# with brownie.reverts("CoffinMakerV2: no pending reward "):
resp = ve_rvrs.claim(_from(1))
assert resp.value == 0

# Turn on rewards and start accruing them for veRvrs contract
# Turn off rewards for auto-rvrs pool
chef.setPool(1, 10, 0, 0, 0, True, _from(0))
chef.setPool(0, 0, 0, 0, 0, True, _from(0))
dummy_token.approve(chef, 1)
chef.deposit(1, 1, ve_rvrs, accounts[0], _from(0))

assert ve_rvrs.rewardsStarted() == False
ve_rvrs.startRewards(_from(0))
ve_rvrs.rewardsStarted() == True

# Print state for debugging
def pp():
    print(f"~~ veRVRS ~~")
    print(f" Total Supply: {ve_rvrs.totalSupply()/1e18:,.4f}")
    print(f" Total Staked: {ve_rvrs.totalStaked()/1e18:,.4f}")
    print(f" RVRS balance: {rvrs.balanceOf(ve_rvrs)/1e18:,.4f}")
    print(f" Pending Rew : {chef.pendingReward(1, ve_rvrs)/1e18:,.4f}")
    for i in range(1,4):
        print(f"~~ User {i} ~~")
        print(f" RVRS wallet: {rvrs.balanceOf(accounts[i])/1e18:,.4f}")
        print(f" RVRS staked: {ve_rvrs.userInfo(accounts[i])[0]/1e18:,.4f}")
        print(f" veRVRS     : {ve_rvrs.balanceOf(accounts[i])/1e18:,.4f}")
        print(f" veRVRS %   : {ve_rvrs.balanceOf(accounts[i])/ve_rvrs.totalSupply()*100:,.2f}%")
        print(f" claimable  : {ve_rvrs.claimable(accounts[i])/1e18:,.4f}")
        print(f" pending    : {ve_rvrs.pendingRewards(accounts[i])/1e18:,.4f}")

pp()


##############################
# Tests
##############################


# Make sure claimable and pending are increasing over time
before_claimable = [ve_rvrs.claimable(accounts[i]) for i in range(1, 4)]
before_pending = [ve_rvrs.pendingRewards(accounts[i]) for i in range(1, 4)]

time.sleep(2)
chain.mine(1)

after_claimable = [ve_rvrs.claimable(accounts[i]) for i in range(1, 4)]
after_pending = [ve_rvrs.pendingRewards(accounts[i]) for i in range(1, 4)]

for pending0, pending1, claim0, claim1 in zip(before_pending, after_pending, before_claimable, after_claimable):
    assert pending1 > pending0, "pending did not increase"
    assert claim1 > claim0, "claimable did not increase"
print("\nPending test success!")
print("Claimable test success!\n")


time.sleep(3)
chain.mine(1)
# Claim and make sure they have more ve_rvrs now
before_vervrs = ve_rvrs.balanceOf(accounts[1])
before_rvrs = rvrs.balanceOf(accounts[1])
before_userInfo = ve_rvrs.userInfo(accounts[1])
resp = ve_rvrs.claim(_from(1))

# Both RVRS and veRVRS should increase
assert ve_rvrs.balanceOf(accounts[1]) > before_vervrs, "didn't get veRVRS"
assert rvrs.balanceOf(accounts[1]) > before_rvrs, "didn't get RVRS"
# All pending should be paid out
assert ve_rvrs.pendingRewards(accounts[1]) == 0, "still has pending??"
assert ve_rvrs.claimable(accounts[1]) == 0, "still has claimable??"
# reward debts should increase
assert ve_rvrs.userInfo(accounts[1])[1] > before_userInfo[1], "No change in reward debt"
assert ve_rvrs.userInfo(accounts[1])[2] > before_userInfo[2], "No change in reward debt"
assert ve_rvrs.userInfo(accounts[1])[3] > before_userInfo[3], "Last claim time not updated"
# Should NOT impact last deposit time
assert ve_rvrs.userInfo(accounts[1])[4] == before_userInfo[4], "Last deposit time updated incorrectly! Should not change"

assert ve_rvrs.balanceOf(accounts[1]) > ve_rvrs.balanceOf(accounts[2]), "bad increases on other accs??"
assert ve_rvrs.balanceOf(accounts[1]) > ve_rvrs.balanceOf(accounts[3]), "bad increases on other accs??"
print("Claim test success!\n")

# Test withdraw slashing
# The user should still get their rewards credit for the veRVRS up to now
# The user should get pending + (1-withdrawFee) * staked
time.sleep(3)
chain.mine(1)
pending_chef_before = chef.pendingReward(1, ve_rvrs)
acc_rew_before = ve_rvrs.accRewardPerShare()
acc_rew_ve_before = ve_rvrs.accRewardPerVeShare()
rew_claimed_before = ve_rvrs.totalRewardsClaimed()
pending = ve_rvrs.pendingRewards(accounts[2])
rvrs_before = rvrs.balanceOf(accounts[2])
rvrs_staked = ve_rvrs.userInfo(accounts[2])[0]

# withdraw 10, should get 9.5 + pending and LOSE ALL veRVRS
resp = ve_rvrs.withdraw(10e18, _from(2))
# All veRVRS should be slashed even for partial withdraw
assert ve_rvrs.balanceOf(accounts[2]) == 0, "veRVRS not slashed!"
# withdraw fee should be sent to multisig
assert rvrs.balanceOf(rvrsDAO) == 5e17, "Bad withdraw fee??"
# User should get all of pending and 95% of withdraw
assert rvrs.balanceOf(accounts[2]) >= rvrs_before + pending + 95e17, "Bad withdraw!"

assert ve_rvrs.claimable(accounts[2]) == 0, "Still pending veRVRS??"
assert ve_rvrs.pendingRewards(accounts[2]) == 0, "Still pending rewards??"
print("Withdraw test success!")
print("Slashing test success!\n")



# Test deposit is updated
time.sleep(3)
chain.mine(1)

before_userInfo = ve_rvrs.userInfo(accounts[3])
pending = ve_rvrs.pendingRewards(accounts[3])
claimable = ve_rvrs.claimable(accounts[3])
vervrs_before = ve_rvrs.balanceOf(accounts[3])
rvrs_before = rvrs.balanceOf(accounts[3])

resp = ve_rvrs.deposit(1e20, _from(3))

assert ve_rvrs.userInfo(accounts[3])[0] == before_userInfo[0] + 1e20, "Deposit not credited"

assert ve_rvrs.userInfo(accounts[3])[1] > before_userInfo[1], "No change in reward debt"
assert ve_rvrs.userInfo(accounts[3])[2] > before_userInfo[2], "No change in reward debt"
# Should update last claim time
assert ve_rvrs.userInfo(accounts[3])[3] > before_userInfo[3], "Last claim time not updated"
assert ve_rvrs.userInfo(accounts[3])[4] > before_userInfo[4], "Last deposit time not updated"

assert ve_rvrs.balanceOf(accounts[3]) >= vervrs_before + claimable + 5e17
assert rvrs.balanceOf(accounts[3]) >= rvrs_before - 1e20 + pending
print("\nRe-deposit test success\n")


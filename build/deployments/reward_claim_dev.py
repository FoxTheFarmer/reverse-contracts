
# from build.deployments.deploy_utils import *
# Accs = setup_mainnet_accounts()


def _from(acc_id):
    return {'from': accounts[acc_id]}

rvrs = ReverseToken.deploy(_from(0))

rvrs.mint(accounts[0], 10000)


rewarder = rewardClaim.deploy(rvrs, _from(0))

rew = [10, 20, 30, 40, 50]
accs = [accounts[i].address for i in range(5)]


rewarder.setRewardAmounts(accs, rew, _from(0))

assert rewarder.rewardDebt() == 150
for acc, amt in zip(accs, rew):
    assert rewarder.claimable(acc) == amt
    assert rewarder.claimed(acc) == 0

# Test claim before rewards are there
resp = rewarder.claim(accs[2], _from(2))
assert resp.status == 0  # should revert with "Out of rewards"

rvrs.transfer(rewarder, 40, _from(0))
resp = rewarder.claim(accs[2], _from(2))
assert resp.status
assert rewarder.claimable(accs[2]) == 0
assert rewarder.claimed(accs[2]) == 30
assert rewarder.rewardDebt() == 120


# Test adding more after claim
rew = [10, 20, 30, 40, 50]
accs = [accounts[i].address for i in range(5)]
rewarder.setRewardAmounts(accs, rew, _from(0))

assert rewarder.claimable(accs[0]) == 20
assert rewarder.claimable(accs[1]) == 40
assert rewarder.claimable(accs[2]) == 30
assert rewarder.claimable(accs[3]) == 80
assert rewarder.claimable(accs[4]) == 100
assert rewarder.rewardDebt() == 270


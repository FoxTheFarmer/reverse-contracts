
from build.deployments.deploy_utils import *

Accs = setup_mainnet_accounts()

WALLET_FILENAME = "../../cryptomerchant/rvrs_wallets.csv"
UST = "0x224e64ec1BDce3870a6a6c777eDd450454068FEC"
RVRS = "0xED0B4b0F0E2c17646682fc98ACe09feB99aF3adE"
TRANQ = "0xCf1709Ad76A79d5a60210F23e81cE2460542A836"

AMT_UST = int(9930e18)
RVRS_PRICE = 0.11130

rewarder = Contract.from_abi("rewardClaim", "0xfaAAB6e4b3165b2f68d3B7bAbb8B1cc68f2f2209", RewardClaim.abi)


print(f"AirDrop UST Amount: {AMT_UST/1e18:,.0f}")

with open(WALLET_FILENAME, 'r') as f:
    data = f.readlines()

wallets = [d.replace("\n", "").split(",") for d in data][::-1]
address_list = [w[0] for w in wallets]
rvrs_amounts = [int(w[1]) for w in wallets]

total_rvrs = sum(rvrs_amounts)
send_amounts = [int(x * AMT_UST / total_rvrs) for x in rvrs_amounts]
apr = AMT_UST/(total_rvrs * RVRS_PRICE) * 100 * 52

print(f"\nSending out ${AMT_UST/1e18:,.0f} UST")
print(f"{len(address_list)} unique addresses with > 20 RVRS")
print(f"Total RVRS staked: {total_rvrs/1e18:,.0f}")
print(f"UST per 10,000 RVRS Staked = ${AMT_UST/total_rvrs*10000:,.2f} (~{apr:.2f}% APR annualized)\n")


network.gas_limit(28888888)
batch_amount = 1000

start = 0
end = batch_amount
print(f"Len of sends [{start}:{end}]: {len(address_list[start:end])}")
resp = rewarder.addRewardAmounts(address_list[start:end], send_amounts[start:end], {'from': Accs.deployer})

start += batch_amount
end += batch_amount
print(f"Len of sends [{start}:{end}]: {len(address_list[start:end])}")

resp = rewarder.addRewardAmounts(address_list[start:end], send_amounts[start:end], {'from': Accs.deployer})

start += batch_amount
end += batch_amount
print(f"Len of sends [{start}:{end}]: {len(address_list[start:end])}")

resp = rewarder.addRewardAmounts(address_list[start:end], send_amounts[start:end], {'from': Accs.deployer})

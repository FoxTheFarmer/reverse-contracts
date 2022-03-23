
from build.deployments.deploy_utils import setup_mainnet_accounts, balanceOf

Accs = setup_mainnet_accounts()

WALLET_FILENAME = "../../cryptomerchant/rvrs_wallets.csv"
UST = "0x224e64ec1BDce3870a6a6c777eDd450454068FEC"
RVRS = "0xED0B4b0F0E2c17646682fc98ACe09feB99aF3adE"
TRANQ = "0xCf1709Ad76A79d5a60210F23e81cE2460542A836"

multisend = Contract.from_abi("MultiSend", "0xDd15f3778D5B67798249361B3dE74aF30D12e084", MultiSend.abi)

# rewarder = Contract.from_abi("rewardClaim", "0xB2817845f448C33516CcC68898ecfE6155A66F45", RewardClaim.abi)
# rewarder = rewardClaim.deploy(UST, {'from': Accs.deployer})

AMT_UST = balanceOf(UST, multisend) - 1e9
print(f"Multisend UST balance: {AMT_UST/1e18:,.0f}")

with open(WALLET_FILENAME, 'r') as f:
    data = f.readlines()

wallets = [d.replace("\n", "").split(",") for d in data][::-1]
address_list = [w[0] for w in wallets]
rvrs_amounts = [int(w[1]) for w in wallets]

total_rvrs = sum(rvrs_amounts)
send_amounts = [int(x * AMT_UST / total_rvrs) for x in rvrs_amounts]

print(f"\nSending out ${AMT_UST/1e18:,.0f} UST")
print(f"{len(address_list)} unique addresses with > 20 RVRS")
print(f"Total RVRS staked: {total_rvrs/1e18:,.0f}")
print(f"UST per 1000 RVRS Staked = ${AMT_UST/total_rvrs*1000:,.2f}\n")


assert balanceOf(UST, multisend) > AMT_UST, "not enough UST!"

network.gas_limit(18888888)
batch_amount = 550

start = 0
end = batch_amount
print(f"Len of sends [{start}:{end}]: {len(address_list[start:end])}")
resp = multisend.sendAll(UST, address_list[start:end], send_amounts[start:end], {'from': Accs.deployer})

start += batch_amount
end += batch_amount
print(f"Len of sends [{start}:{end}]: {len(address_list[start:end])}")

resp = multisend.sendAll(UST, address_list[start:end], send_amounts[start:end], {'from': Accs.deployer})

start += batch_amount
end += batch_amount
print(f"Len of sends [{start}:{end}]: {len(address_list[start:end])}")

resp = multisend.sendAll(UST, address_list[start:end], send_amounts[start:end], {'from': Accs.deployer})


start += batch_amount
end += batch_amount
print(f"Len of sends [{start}:{end}]: {len(address_list[start:end])}")

resp = multisend.sendAll(UST, address_list[start:end], send_amounts[start:end], {'from': Accs.deployer})

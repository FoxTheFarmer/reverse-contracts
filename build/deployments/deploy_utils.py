
from brownie import accounts
from brownie.network.account import LocalAccount
from dataclasses import dataclass


@dataclass
class Accounts:
    deployer: LocalAccount
    dev: LocalAccount
    user1: LocalAccount = None
    user2: LocalAccount = None
    user3: LocalAccount = None


def setup_mainnet_accounts():
    accounts.load('revdep')
    accounts.load('mainnet-dev')
    return Accounts(accounts[0], accounts[1])

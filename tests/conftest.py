import pytest
from ape import networks, Contract


# WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

@pytest.fixture
def bob(accounts):
    # private 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    bob = accounts['0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266']
    bob.balance += int(10000e18)
    return bob


@pytest.fixture
def alice(accounts):
    #private 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
    alice = accounts['0x70997970C51812dc3A010C7d01b50e0d17dc79C8']
    alice.balance += int(10000e18)
    return alice


# @pytest.fixture
# def fork_weth():
#     return Contract(WETH)

@pytest.fixture
def weth(project, bob):
    return bob.deploy(project.WETH9)

@pytest.fixture
def vault(project, bob, weth):
    return bob.deploy(project.NadFinanceVault, weth.address)


@pytest.fixture
def pool_master(project, bob, vault):
    return bob.deploy(project.NadFinancePoolMaster, vault)


@pytest.fixture
def crypto_pool(project, bob):
    return bob.deploy(project.NadFinanceCryptoPool)


@pytest.fixture
def crypto_pool_factory(project, bob, pool_master, crypto_pool):
    factory = bob.deploy(project.NadFinanceCryptoPoolFactory, pool_master, crypto_pool)
    pool_master.set_factory_whitelisted(factory.address, True, sender=bob)
    return factory


@pytest.fixture
def stable_pool(project, bob):
    return bob.deploy(project.NadFinanceStablePool)
    

@pytest.fixture
def stable_pool_factory(project, bob, pool_master, stable_pool):
    factory = bob.deploy(project.NadFinanceStablePoolFactory, pool_master, stable_pool)
    pool_master.set_factory_whitelisted(factory.address, True, sender=bob)
    return factory


@pytest.fixture
def router(project, bob, vault, weth):
    return bob.deploy(project.NadFinanceRouter, vault.address, weth.address)


@pytest.fixture
def test_token0(project, bob):
    return bob.deploy(project.TestToken, "token0", "t0")


@pytest.fixture
def test_token1(project, bob):
    return bob.deploy(project.TestToken, "token1", "t1")


@pytest.fixture
def w3():
    return networks.provider._web3



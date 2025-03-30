#pragma version 0.4.0

from ethereum.ercs import IERC20


interface IPoolMaster:
    def get_swap_fee(
        _pool: address,
        _sender: address,
        _token_in: address,
        _token_out: address,
        _data: Bytes[1_024]
    ) -> uint24: view
    def register_pool(_pool: address, _pool_type: uint16, _data: Bytes[1_024]): nonpayable

interface IPool:
    def initialize(): nonpayable


event CreatePool:
    tokenA: indexed(address)
    tokenB: indexed(address)
    pool: address


master: public(immutable(address))
crypto_pool: public(immutable(address))
cache_deploy_data: Bytes[1_024]
get_pool: public(HashMap[address, HashMap[address, address]])


@deploy
@payable 
def __init__(_master: address, _crypto_pool: address):
    master = _master
    crypto_pool = _crypto_pool


@view 
@external 
def get_deploy_data() -> Bytes[1_024]:
    return self.cache_deploy_data


@view
@external 
def get_swap_fee(
    _pool: address,
    _sender: address,
    _token_in: address,
    _token_out: address,
    _data: Bytes[1_024]
) -> uint24:
    return staticcall IPoolMaster(master).get_swap_fee(_pool, _sender, _token_in, _token_out, _data)


@internal 
def _create_pool(_tokenA: address, _tokenB: address) -> address:
    assert staticcall IERC20(_tokenA).balanceOf(self) >= 0
    assert staticcall IERC20(_tokenB).balanceOf(self) >= 0

    deploy_data: Bytes[1_024] = abi_encode(_tokenA, _tokenB)
    self.cache_deploy_data = deploy_data

    salt: bytes32 = keccak256(deploy_data)
    pool: address = create_minimal_proxy_to(crypto_pool, salt=salt)
    extcall IPool(pool).initialize()
    extcall IPoolMaster(master).register_pool(pool, 1, deploy_data)

    return pool


@external
def create_pool(_data: Bytes[1_024]) -> address:
    tokenA: address = empty(address)
    tokenB: address = empty(address)
    tokenA, tokenB = abi_decode(_data, (address, address))

    assert tokenA != tokenB, "Invalid tokens"

    token0: address = empty(address)
    token1: address = empty(address)
    if convert(tokenB, uint256) < convert(tokenA, uint256):
        token0 = tokenB
        token1 = tokenA
    else:
        token0 = tokenA
        token1 = tokenB

    assert token0 != empty(address), "Invalid tokens"

    pool: address = self._create_pool(token0, token1)

    self.get_pool[token0][token1] = pool
    self.get_pool[token1][token0] = pool

    log CreatePool(token0, token1, pool)

    return pool


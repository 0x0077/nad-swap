#pragma version 0.4.0

from ethereum.ercs import IERC20
from ethereum.ercs import IERC20Detailed
from snekmate.utils import signature_checker

implements: IERC20
implements: IERC20Detailed

interface IPoolFactory:
    def get_deploy_data() -> Bytes[1_024]: view
    def master() -> address: view

interface IPoolMaster:
    def vault() -> address: view
    def is_forwarder(_forwarder: address) -> bool: view
    def get_fee_recipient() -> address: view
    def get_protocol_fee() -> uint24: view
    def get_swap_fee(_pool: address, _sender: address, _token_in: address, _token_out: address, _data: Bytes[1_024]) -> uint24: view
    def notify_fees(_fee_type: uint16, _token: address, _amount: uint256, _fee_rate: uint256, _data: Bytes[1_024]): nonpayable

interface IVault:
    def transfer(_token: address, _to: address, _amount: uint256): nonpayable
    def withdraw_alternative(_token: address, _to: address, _amount: uint256, _mode: uint8): nonpayable
    def balanceOf(_token: address, _owner: address) -> uint256: view

interface ICallback:
    def nad_base_mint_callback(_params: BaseMintCallbackParams): nonpayable
    def nad_base_burn_callback(_params: BaseBurnCallbackParams): nonpayable
    def nad_base_burn_single_callback(_params: BaseBurnSingleCallbackParams): nonpayable
    def nad_base_swap_callback(_params: BaseSwapCallbackParams): nonpayable

interface ERC1271:
    def isValidSignature(_hash: bytes32, _signature: Bytes[65]) -> bytes4: view

struct BaseMintCallbackParams:
    sender: address
    to: address
    reserve0: uint256
    reserve1: uint256
    balance0: uint256
    balance1: uint256
    amount0: uint256
    amount1: uint256
    fee0: uint256
    fee1: uint256
    new_invariant: uint256 
    old_invariant: uint256
    total_supply: uint256
    liquidity: uint256
    swap_fee: uint24
    callback_data: Bytes[1_024]

struct BaseBurnCallbackParams:
    sender: address
    to: address
    balance0: uint256
    balance1: uint256
    liquidity: uint256
    total_supply: uint256
    amount0: uint256
    amount1: uint256
    withdraw_mode: uint8
    callback_data: Bytes[1_024]

struct BaseBurnSingleCallbackParams:
    sender: address
    to: address
    token_in: address
    token_out: address
    balance0: uint256
    balance1: uint256
    liquidity: uint256
    total_supply: uint256
    amount0: uint256
    amount1: uint256
    amount_out: uint256
    amount_swapped: uint256
    fee_in: uint256
    swap_fee: uint24
    withdraw_mode: uint8
    callback_data: Bytes[1_024]

struct BaseSwapCallbackParams:
    sender: address
    to: address
    token_in: address
    token_out: address
    reserve0: uint256
    reserve1: uint256
    balance0: uint256
    balance1: uint256
    amount_in: uint256
    amount_out: uint256
    fee_in: uint256
    swap_fee: uint24
    withdraw_mode: uint8
    callback_data: Bytes[1_024]

struct TokenAmount:
    token: address
    amount: uint256

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event Mint:
    sender: indexed(address)
    amount0: uint256
    amount1: uint256
    liquidity: uint256
    to: address

event Burn:
    sender: indexed(address)
    amount0: uint256
    amount1: uint256
    liquidity: uint256
    to: address

event Swap:
    sender: indexed(address)
    amount0In: uint256
    amount1In: uint256
    amount0Out: uint256
    amount1Out: uint256
    to: address 

event Sync:
    reserve0: uint256
    reserve1: uint256

version: public(constant(String[8])) = "v1.0.0"

ERC1271_MAGIC_VAL: constant(bytes4) = 0x1626ba7e
EIP712_TYPEHASH: constant(bytes32) = keccak256(
    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
)
EIP2612_TYPEHASH: constant(bytes32) = keccak256(
    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
)
VERSION_HASH: constant(bytes32) = keccak256(version)
salt: bytes32
name_hash: bytes32
cached_chain_id: uint256
cached_domain_separator: bytes32
nonces: public(HashMap[address, uint256])


name: public(String[32])
symbol: public(String[32])
decimals: public(uint8)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
totalSupply: public(uint256)

MAXIMUN_XP: constant(uint256) = 3802571709128108338056982581425910818
MINIMUM_LIQUIDITY: constant(uint256) = 1000
MAX_FEE: constant(uint256) = 100000

pool_type: public(constant(uint16)) = 2

master: public(address)
vault: public(address)
token0: public(address)
token1: public(address)

token0_precision_multipliter: public(uint256)
token1_precision_multipliter: public(uint256)

reserve0: public(uint256)
reserve1: public(uint256)
invariant_last: public(uint256)
initialized: public(bool)

@external
def initialize():
    assert not self.initialized, "Already Initialized"
    deploy_data: Bytes[1_024] = staticcall IPoolFactory(msg.sender).get_deploy_data()

    _token0: address = empty(address)
    _token1: address = empty(address)
    _token0_precision_multiplier: uint256 = empty(uint256)
    _token1_precision_multiplier: uint256 = empty(uint256)
    _token0, _token1, _token0_precision_multiplier, _token1_precision_multiplier = abi_decode(deploy_data, (address, address, uint256, uint256))
    
    _master: address = staticcall IPoolFactory(msg.sender).master()
    self.master = _master
    self.vault = staticcall IPoolMaster(_master).vault()
    self.token0 = _token0
    self.token1 = _token1
    self.token0_precision_multipliter = _token0_precision_multiplier
    self.token1_precision_multipliter = _token1_precision_multiplier

    _name: String[32] = "NadFi Stable LP V1"
    self.name = _name
    self.symbol = "nSLP-V1"
    self.decimals = 18
    self.name_hash = keccak256(_name)
    self.cached_chain_id = chain.id
    self.salt = block.prevhash
    self.cached_domain_separator = keccak256(
        abi_encode(
            EIP712_TYPEHASH,
            keccak256(_name),
            VERSION_HASH,
            chain.id,
            self,
            block.prevhash
        )
    )
    self.initialized = True


@external
def transfer(_to : address, _amount : uint256) -> bool:
    self.balanceOf[msg.sender] -= _amount
    self.balanceOf[_to] += _amount
    log Transfer(msg.sender, _to, _amount)
    return True


@external
def transferFrom(_from : address, _to : address, amount : uint256) -> bool:
    self.balanceOf[_from] -= amount
    self.balanceOf[_to] += amount
    self.allowance[_from][msg.sender] -= amount
    log Transfer(_from, _to, amount)
    return True


@external
def approve(spender: address, amount: uint256) -> bool:
    self._approve(msg.sender, spender, amount)
    return True


@external
def permit(
    _owner: address,
    _spender: address,
    _value: uint256,
    _deadline: uint256,
    _v: uint8,
    _r: bytes32,
    _s: bytes32,
) -> bool:
    assert _owner != empty(address) and block.timestamp <= _deadline

    nonce: uint256 = self.nonces[_owner]
    digest: bytes32 = keccak256(
        concat(
            b"\x19\x01",
            self._domain_separator(),
            keccak256(abi_encode(EIP2612_TYPEHASH, _owner, _spender, _value, nonce, _deadline)),
        )
    )

    if _owner.is_contract:
        sig: Bytes[65] = concat(abi_encode(_r, _s), slice(convert(_v, bytes32), 31, 1))
        assert staticcall ERC1271(_owner).isValidSignature(digest, sig) == ERC1271_MAGIC_VAL
    else:
        assert ecrecover(digest, _v, _r, _s) == _owner

    self.nonces[_owner] = nonce + 1
    self._approve(_owner, _spender, _value)
    return True


@external
def permit2(
    _owner: address,
    _spender: address,
    _value: uint256,
    _deadline: uint256,
    _signature: Bytes[65]
) -> bool:
    assert _owner != empty(address) and block.timestamp <= _deadline

    nonce: uint256 = self.nonces[_owner]
    digest: bytes32 = keccak256(
        concat(
            b"\x19\x01",
            self._domain_separator(),
            keccak256(abi_encode(EIP2612_TYPEHASH, _owner, _spender, _value, nonce, _deadline)),
        )
    )
    
    assert signature_checker._is_valid_signature_now(_owner, digest, _signature), "Invalid Signature"

    self.nonces[_owner] = nonce + 1
    self._approve(_owner, _spender, _value)
    return True


@internal
def _approve(_owner: address, _spender: address, _value: uint256):
    self.allowance[_owner][_spender] = _value

    log Approval(_owner, _spender, _value)


@internal
def _mint(_to : address, amount : uint256):
    self.balanceOf[_to] += amount
    self.totalSupply += amount
    log Transfer(empty(address), _to, amount)


@internal
def _burn(_from: address, amount: uint256):
    self.balanceOf[_from] -= amount
    self.totalSupply -= amount
    log Transfer(_from, empty(address), amount)


@view
@internal
def _domain_separator() -> bytes32:
    if chain.id != self.cached_chain_id:
        return keccak256(
            abi_encode(
                EIP712_TYPEHASH,
                self.name_hash,
                VERSION_HASH,
                chain.id,
                self,
                self.salt,
            )
        )
    return self.cached_domain_separator


@pure 
@internal 
def _with_in1(_a: uint256, _b: uint256) -> bool:
    if _a > _b:
        return _a - _b <= 1
    return _b - _a <= 1


@pure
@internal 
def _compute_d_from_adjusted_balances(_xp0: uint256, _xp1: uint256) -> uint256:
    computed: uint256 = empty(uint256)
    s: uint256 = _xp0 + _xp1

    if s == 0:
        computed = 0
    else:
        prev_d: uint256 = empty(uint256)
        d: uint256 = s 

        for i: uint256 in range(256):
            dp: uint256 = (((d * d) // _xp0) * d) // _xp1 // 4
            prev_d = d 
            d = (((2000 * s) + 2 * dp) * d) // (1999 * d + 3 * dp)
            
            if self._with_in1(d, prev_d):
                break

        computed = d 

    return computed


@pure 
@internal 
def _get_y(_x: uint256, _d: uint256) -> uint256:
    y: uint256 = empty(uint256)
    c: uint256= unsafe_div(unsafe_mul(_d, _d), unsafe_mul(2, _x))
    c = unsafe_div(unsafe_mul(c, _d), 4000)

    b: uint256 = _x + unsafe_div(_d, 2000)
    y_prev: uint256 = empty(uint256)
    y = _d

    for i: uint256 in range(256):
        y_prev = y 
        y = unsafe_div(unsafe_add(unsafe_mul(y, y), c), unsafe_mul(y, 2) + b - _d)

        if self._with_in1(y, y_prev):
            break
    
    return y


@view
@external 
def getAssets() -> (address, address):
    return (self.token0, self.token1) 


@view
@external
def get_reserves() -> (uint256, uint256):
    return self.reserve0, self.reserve1


@view 
@external 
def get_swap_fee(_sender: address, _token_in: address, _token_out: address, _data: Bytes[1_024]) -> uint24:
    return staticcall IPoolMaster(self.master).get_swap_fee(self, _sender, _token_in, _token_out, _data)


@view 
@external 
def get_protocol_fee() -> uint24:
    return self._get_protocol_fee()


@view 
@external 
def get_amount_out(_token_in: address, _amount_in: uint256, _sender: address) -> uint256:
    _reserve0: uint256 = self.reserve0
    _reserve1: uint256 = self.reserve1

    _swap0_for1: bool = False
    if _token_in == self.token0:
        _swap0_for1 = True

    _token_out: address = empty(address)
    if _swap0_for1:
        _token_out = self.token1
    else:
        _token_out = self.token0
    
    amount_out: uint256 = empty(uint256)
    fee_in: uint256 = empty(uint256)
    swap_fee: uint256 = convert(self._get_swap_fee(_sender, _token_in, _token_out), uint256)
    amount_out, fee_in = self._get_amount_out(swap_fee, _amount_in, _reserve0, _reserve1, _swap0_for1)

    return amount_out


@view 
@external 
def get_amount_in(_token_out: address, _amount_out: uint256, _sender: address) -> uint256:
    _reserve0: uint256 = self.reserve0
    _reserve1: uint256 = self.reserve1

    swap1_for0: bool = False
    if _token_out == self.token0:
        swap1_for0 = True
    
    _token_in: address = empty(address)
    if swap1_for0:
        _token_in = self.token1
    else:
        _token_in = self.token0
    
    swap_fee: uint256 = convert(self._get_swap_fee(_sender, _token_in, _token_out), uint256)
    amount_in: uint256 = self._get_amount_in(swap_fee, _amount_out, _reserve0, _reserve1, swap1_for0)

    return amount_in


@view 
@internal 
def _get_swap_fee(_sender: address, _token_in: address, _token_out: address) -> uint24:
    return staticcall IPoolMaster(self.master).get_swap_fee(self, _sender, _token_in, _token_out, b"")


@view 
@internal 
def _get_verified_sender(_sender: address) -> address:
    if _sender != empty(address):
        if _sender != msg.sender:
            if not staticcall IPoolMaster(self.master).is_forwarder(msg.sender):
                return empty(address)
    return _sender


@view
@internal 
def _balances() -> (uint256, uint256):
    balance0: uint256 = staticcall IVault(self.vault).balanceOf(self.token0, self)
    balance1: uint256 = staticcall IVault(self.vault).balanceOf(self.token1, self)
    return balance0, balance1


@view
@internal 
def _get_protocol_fee() -> uint24:
    return staticcall IPoolMaster(self.master).get_protocol_fee()


@view
@internal 
def _get_amount_out(
    _swap_fee: uint256,
    _amount_in: uint256,
    _reserve0: uint256,
    _reserve1: uint256,
    _token0_in: bool
) -> (uint256, uint256):
    dy: uint256 = empty(uint256)
    fee_in: uint256 = empty(uint256)

    if _amount_in == 0:
        dy = 0
    else:
        adjusted_reserve0: uint256 = _reserve0 * self.token0_precision_multipliter
        adjusted_reserve1: uint256 = _reserve1 * self.token1_precision_multipliter

        fee_in = (_amount_in * _swap_fee) // MAX_FEE
        fee_deducted_amount_in: uint256 = _amount_in - fee_in
        d: uint256 = self._compute_d_from_adjusted_balances(adjusted_reserve0, adjusted_reserve1)

        if _token0_in:
            x: uint256 = adjusted_reserve0 + (fee_deducted_amount_in * self.token0_precision_multipliter)
            y: uint256 = self._get_y(x, d)
            dy = adjusted_reserve1 - y - 1
            dy //= self.token1_precision_multipliter
        else:
            x: uint256 = adjusted_reserve1 + (fee_deducted_amount_in * self.token1_precision_multipliter)
            y: uint256 = self._get_y(x, d)
            dy = adjusted_reserve0 - y - 1
            dy //= self.token0_precision_multipliter

    return dy, fee_in


@view 
@internal 
def _get_amount_in(
    _swap_fee: uint256,
    _amount_out: uint256,
    _reserve0: uint256,
    _reserve1: uint256,
    _token0_out: bool
) -> uint256:
    dx: uint256 = empty(uint256)
    if _amount_out == 0:
        dx = 0
    else:
        adjusted_reserve0: uint256 = _reserve0 * self.token0_precision_multipliter
        adjusted_reserve1: uint256 = _reserve1 * self.token1_precision_multipliter
        d: uint256 = self._compute_d_from_adjusted_balances(adjusted_reserve0, adjusted_reserve1)

        if _token0_out:
            y: uint256 = adjusted_reserve0 - (_amount_out * self.token0_precision_multipliter)
            if y <= 1:
                return 1
            
            x: uint256 = self._get_y(y, d)
            dx = MAX_FEE * (x - adjusted_reserve1) // (MAX_FEE - _swap_fee) + 1
            dx //= self.token1_precision_multipliter
        else:
            y: uint256 = adjusted_reserve1 - (_amount_out * self.token1_precision_multipliter)
            if y <= 1:
                return 1
            
            x: uint256 = self._get_y(y, d)
            dx = MAX_FEE * (x - adjusted_reserve0) // (MAX_FEE - _swap_fee) + 1
            dx //= self.token0_precision_multipliter

    return dx


@pure
@internal 
def _unbalance_mint_fee(
    _swap_fee: uint256,
    _amount0: uint256,
    _amount1: uint256,
    _amount1_optimal: uint256,
    _reserve0: uint256,
    _reserve1: uint256
) -> (uint256, uint256):
    if _reserve0 == 0:
        return 0, 0

    _token0_fee: uint256 = empty(uint256)
    _token1_fee: uint256 = empty(uint256)

    if _amount1 >= _amount1_optimal:
        _token1_fee = (_swap_fee * (_amount1 - _amount1_optimal)) // (2 * MAX_FEE)
    else:
        _amount0_optimal: uint256 = (_amount1 * _reserve0) // _reserve1
        _token0_fee = (_swap_fee * (_amount0 - _amount0_optimal)) // (2 * MAX_FEE)
    
    return _token0_fee, _token1_fee


@view
@internal 
def _compute_invariant(_reserve0: uint256, _reserve1: uint256) -> uint256:
    adjusted_reserve0: uint256 = _reserve0 * self.token0_precision_multipliter
    adjusted_reserve1: uint256 = _reserve1 * self.token1_precision_multipliter

    assert adjusted_reserve0 <= MAXIMUN_XP, "Overflow"
    assert adjusted_reserve1 <= MAXIMUN_XP, "Overflow"
    return self._compute_d_from_adjusted_balances(adjusted_reserve0, adjusted_reserve1)


@internal 
def _update_reserves(_balance0: uint256, _balance1: uint256):
    self.reserve0 = _balance0
    self.reserve1 = _balance1
    log Sync(_balance0, _balance1)


@internal
def _transfer_tokens(_token: address, _to: address, _amount: uint256, _withdraw_mode: uint8):
    if _withdraw_mode == 0:
        extcall IVault(self.vault).transfer(_token, _to, _amount)
    else:
        extcall IVault(self.vault).withdraw_alternative(_token, _to, _amount, _withdraw_mode)


@internal 
def _mint_protocol_fee(_reserve0: uint256, _reserve1: uint256, _invariant: uint256) -> (bool, uint256):
    _total_supply: uint256 = self.totalSupply

    _fee_recipient: address = staticcall IPoolMaster(self.master).get_fee_recipient()
    _fee_on: bool = False
    if _fee_recipient != empty(address):
        _fee_on = True

    _invariant_last: uint256 = self.invariant_last
    if _invariant_last != 0:
        if _fee_on:
            new_invariant: uint256 = _invariant
            if new_invariant == 0:
                new_invariant = self._compute_invariant(_reserve0, _reserve1)

            if new_invariant > _invariant_last:
                protocol_fee: uint256 = convert(self._get_protocol_fee(), uint256)
                numerator: uint256 = _total_supply * (new_invariant - _invariant_last) * protocol_fee
                denominator: uint256 = (MAX_FEE - protocol_fee) * new_invariant + protocol_fee * _invariant_last
                liquidity: uint256 = numerator // denominator

                if liquidity != 0:
                    self._mint(_fee_recipient, liquidity)

                    extcall IPoolMaster(self.master).notify_fees(2, self, liquidity, protocol_fee, b"")

                    _total_supply += liquidity

        else:
            _invariant_last = 0

    return _fee_on, _total_supply
                    

@external
@nonreentrant 
def mint(_data: Bytes[1_024], _sender: address, _callback: address, _callback_data: Bytes[1_024]) -> uint256:
    params: BaseMintCallbackParams = empty(BaseMintCallbackParams)

    params.to = abi_decode(_data, (address))
    params.reserve0 = self.reserve0
    params.reserve1 = self.reserve1
    params.balance0, params.balance1 = self._balances()

    params.new_invariant = self._compute_invariant(params.balance0, params.balance1)
    params.amount0 = params.balance0 - params.reserve0
    params.amount1 = params.balance1 - params.reserve1

    verified_sender: address = self._get_verified_sender(_sender)
    amount1_optimal: uint256 = empty(uint256)
    if params.reserve0 == 0:
        amount1_optimal = 0
    else:
        amount1_optimal = params.amount0 * params.reserve1 // params.reserve0
    
    swap0_for1: bool = False
    if params.amount1 < amount1_optimal:
        swap0_for1 = True

    if swap0_for1:
        params.swap_fee = self._get_swap_fee(_sender, self.token0, self.token1)
    else:
        params.swap_fee = self._get_swap_fee(_sender, self.token1, self.token0)

    params.fee0, params.fee1 = self._unbalance_mint_fee(convert(params.swap_fee, uint256), params.amount0, params.amount1, amount1_optimal, params.reserve0, params.reserve1)
    params.reserve0 += params.fee0
    params.reserve1 += params.fee1

    params.old_invariant = self._compute_invariant(params.reserve0, params.reserve1)
    fee_on: bool = False
    fee_on, params.total_supply = self._mint_protocol_fee(0, 0, params.old_invariant)

    if params.total_supply == 0:
        params.liquidity = params.new_invariant - MINIMUM_LIQUIDITY
        self._mint(empty(address), MINIMUM_LIQUIDITY)
    else:
        params.liquidity = ((params.new_invariant - params.old_invariant) * params.total_supply) // params.old_invariant
    
    assert params.liquidity != 0, "Insufficient Liquidity Minted"

    self._mint(params.to, params.liquidity)

    if _callback != empty(address):
        params.sender = _sender
        params.callback_data = _callback_data
        extcall ICallback(_callback).nad_base_mint_callback(params)
    
    self._update_reserves(params.balance0, params.balance1)

    if fee_on:
        self.invariant_last = params.new_invariant
    
    log Mint(msg.sender, params.amount0, params.amount1, params.liquidity, params.to)
    return params.liquidity


@external 
@nonreentrant 
def burn(_data: Bytes[1_024], _sender: address, _callback: address, _callback_data: Bytes[1_024]) -> DynArray[TokenAmount, 2]:
    params: BaseBurnCallbackParams = empty(BaseBurnCallbackParams)

    params.to, params.withdraw_mode = abi_decode(_data, (address, uint8))
    params.balance0, params.balance1 = self._balances()
    params.liquidity = self.balanceOf[self]

    fee_on: bool = False
    fee_on, params.total_supply = self._mint_protocol_fee(params.balance0, params.balance1, 0)

    params.amount0 = params.liquidity * params.balance0 // params.total_supply
    params.amount1= params.liquidity * params.balance1 // params.total_supply

    self._burn(self, params.liquidity)
    self._transfer_tokens(self.token0, params.to, params.amount0, params.withdraw_mode)
    self._transfer_tokens(self.token1, params.to, params.amount1, params.withdraw_mode)

    params.balance0 -= params.amount0
    params.balance1 -= params.amount1

    if _callback != empty(address):
        params.sender = self._get_verified_sender(_sender)
        params.callback_data = _callback_data
        extcall ICallback(_callback).nad_base_burn_callback(params)

    self._update_reserves(params.balance0, params.balance1)

    if fee_on:
        self.invariant_last = self._compute_invariant(params.balance0, params.balance1)

    amounts: DynArray[TokenAmount, 2] = []
    amounts.append(TokenAmount(token=self.token0, amount=params.amount0))
    amounts.append(TokenAmount(token=self.token1, amount=params.amount1))

    log Burn(msg.sender, params.amount0, params.amount1, params.liquidity, params.to)

    return amounts


@external 
@nonreentrant 
def burn_single(_data: Bytes[1_024], _sender: address, _callback: address, _callback_data: Bytes[1_024]) -> TokenAmount:
    params: BaseBurnSingleCallbackParams = empty(BaseBurnSingleCallbackParams)

    params.token_out, params.to, params.withdraw_mode = abi_decode(_data, (address, address, uint8))
    params.balance0, params.balance1 = self._balances()
    params.liquidity = self.balanceOf[self]

    fee_on: bool = False
    fee_on, params.total_supply = self._mint_protocol_fee(params.balance0, params.balance1, 0)

    params.amount0 = params.liquidity * params.balance0 // params.total_supply
    params.amount1 = params.liquidity * params.balance1 // params.total_supply

    self._burn(self, params.liquidity)
    verified_sender: address = self._get_verified_sender(_sender)

    if params.token_out == self.token1:
        params.swap_fee = self._get_swap_fee(verified_sender, self.token0, self.token1)

        params.token_in= self.token0
        params.amount_swapped, params.fee_in = self._get_amount_out(
            convert(params.swap_fee, uint256), params.amount0, params.balance0 - params.amount0, params.balance1 - params.amount1, True
        )
        params.amount1 += params.amount_swapped

        self._transfer_tokens(self.token1, params.to, params.amount1, params.withdraw_mode)
        params.amount_out = params.amount1
        params.amount0 = 0
        params.balance1 -= params.amount1

    else:
        params.swap_fee = self._get_swap_fee(verified_sender, self.token1, self.token0)
        params.token_in = self.token1
        params.amount_swapped, params.fee_in = self._get_amount_out(
            convert(params.swap_fee, uint256), params.amount1, params.balance0 - params.amount0, params.balance1 - params.amount1, False
        )
        params.amount0 += params.amount_swapped

        self._transfer_tokens(self.token0, params.to, params.amount0, params.withdraw_mode)
        params.amount_out = params.amount0
        params.amount1 = 0
        params.balance1 -= params.amount0

    if _callback != empty(address):
        params.sender = verified_sender
        params.callback_data = _callback_data

        extcall ICallback(_callback).nad_base_burn_single_callback(params)

    self._update_reserves(params.balance0, params.balance1)

    if fee_on:
        self.invariant_last = self._compute_invariant(params.balance0, params.balance1)

    token_amount: TokenAmount = TokenAmount(token=params.token_out, amount=params.amount_out)

    log Burn(msg.sender, params.amount0, params.amount1, params.liquidity, params.to)
    return token_amount


@external 
@nonreentrant 
def swap(_data: Bytes[1_024], _sender: address, _callback: address, _callback_data: Bytes[1_024]) -> TokenAmount:
    params: BaseSwapCallbackParams = empty(BaseSwapCallbackParams)

    params.token_in, params.to, params.withdraw_mode = abi_decode(_data, (address, address, uint8))
    params.reserve0 = self.reserve0
    params.reserve1 = self.reserve1
    params.balance0, params.balance1 = self._balances()

    verified_sender: address = self._get_verified_sender(_sender)

    if params.token_in == self.token0:
        params.swap_fee = self._get_swap_fee(verified_sender, self.token0, self.token1)
        params.token_out = self.token1
        params.amount_in = params.balance0 - params.reserve0

        params.amount_out, params.fee_in = self._get_amount_out(
            convert(params.swap_fee, uint256), params.amount_in, params.reserve0, params.reserve1, True
        )
        params.balance1 -= params.amount_out

        log Swap(msg.sender, params.amount_in, 0, 0, params.amount_out, params.to)
    
    else:
        params.swap_fee = self._get_swap_fee(verified_sender, self.token1, self.token0)
        params.token_out = self.token0
        params.amount_in = params.balance1 - params.reserve1

        params.amount_out, params.fee_in = self._get_amount_out(
            convert(params.swap_fee, uint256), params.amount_in, params.reserve0, params.reserve1, False
        )
        params.balance0 -= params.amount_out

        log Swap(msg.sender, 0, params.amount_in, params.amount_out, 0, params.to)


    assert params.balance0 * self.token0_precision_multipliter <= MAXIMUN_XP, "Overflow"
    assert params.balance1 * self.token1_precision_multipliter <= MAXIMUN_XP, "Overflow"

    self._transfer_tokens(params.token_out, params.to, params.amount_out, params.withdraw_mode)

    if _callback != empty(address):
        params.sender = verified_sender
        params.callback_data = _callback_data

        extcall ICallback(_callback).nad_base_swap_callback(params)

    self._update_reserves(params.balance0, params.balance1)

    token_amount: TokenAmount = TokenAmount(token=params.token_out, amount=params.amount_out)
    return token_amount
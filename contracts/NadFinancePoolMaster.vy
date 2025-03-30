#pragma version 0.4.0

from ethereum.ercs import IERC20

interface IPool:
    def pool_type() -> uint16: view

interface IPoolFactory:
    def create_pool(_data: Bytes[1_024]) -> address: nonpayable

event AddForwarder:
    forwarder: indexed(address)

event RemoveForwarder:
    forwarder: indexed(address)

event SetDefaultSwapFee:
    pool_type: indexed(uint16)
    fee: uint24

event SetTokenSwapFee:
    token_in: indexed(address)
    token_out: indexed(address)
    fee: uint24

event SetDefaultProtocolFee:
    pool_type: indexed(uint16)
    fee: uint24

event SetPoolProtocolFee:
    pool: indexed(address)
    fee: uint24

event SetFeeRecipient:
    previous_fee_recipient: indexed(address)
    new_fee_recipient: indexed(address)

event SetSenderWhitelisted:
    sender: indexed(address)
    is_whitelisted: indexed(bool)

event NotifyFees:
    sender: indexed(address)
    fee_type: indexed(uint16)
    token: indexed(address)
    amount: uint256
    fee_rate: uint256

event AddFeeDistributor:
    distributor: indexed(address)

event RemoveFeeDistributor:
    distributor: indexed(address)

event SetEpochDuration:
    epoch_duration: indexed(uint256)

event SetFactoryWhitelisted:
    factory: indexed(address)
    whitelisted: bool

event RegisterPool:
    factory: indexed(address)
    pool: indexed(address)
    pool_type: uint16
    data: Bytes[1_024]

struct FeeTokenData:
    start_time: uint256
    amount: uint256


# fee manager
MAX_PROTOCOL_FEE: constant(uint24) = 100000
MAX_SWAP_FEE: constant(uint24) = 10000
ZERO_CUSTOM_FEE: constant(uint24) = max_value(uint24)

default_swap_fee: public(HashMap[uint16, uint24]) # 300 for 0.3%
# The custom swap fee by tokens, use `ZERO_CUSTOM_FEE` for zero fee.
token_swap_fee: public(HashMap[address, HashMap[address, uint24]])
default_protocol_fee: public(HashMap[uint16, uint24]) # 30000 for 30%
pool_protocol_fee: public(HashMap[address, uint24])

is_sender_whitelisted: public(HashMap[address, bool])
fees: public(HashMap[uint256, HashMap[address, uint256]])
fee_tokens: public(HashMap[uint256, DynArray[address, max_value(uint16)]])
is_fee_distributor: HashMap[address, bool]
fee_distributors: public(DynArray[address, max_value(uint16)])

fee_token_data: public(HashMap[address, HashMap[address, FeeTokenData]])

fee_recipient: public(address)
epoch_duration: public(uint256)

# pool manager
vault: public(immutable(address))
owner: public(address)

is_factory_whitelisted: public(HashMap[address, bool])
is_pool: public(HashMap[address, bool])
is_forwarder: public(HashMap[address, bool])
get_pool: public(HashMap[bytes32, address])
pools: public(DynArray[address, 2**32])


@deploy 
@payable 
def __init__(_vault: address):
    vault = _vault
    self.fee_recipient = self

    # Prefill fees for known pool types.
    # 1 => crypto pools
    self.default_swap_fee[1] = 200 # 0.2%
    self.default_protocol_fee[1] = 50000 # 50%

    # 2 => stable pools
    self.default_swap_fee[2] = 40 # 0.04%
    self.default_protocol_fee[2] = 50000 # 50%

    self.owner = msg.sender
    self.epoch_duration = 86400 * 3


#############################################################
#                    SAFE IERC20 LOGIC
#############################################################

@internal
def _safe_transfer(_token: address, _to: address, _amount: uint256):
    response: Bytes[32] = b""
    success: bool = False
    success, response = raw_call(
        _token,
        abi_encode(
            _to,
            _amount,
            method_id=method_id("transfer(address,uint256)")
        ),
        max_outsize=32,
        revert_on_failure=False
    )

    assert success and (len(response) > 0 and convert(response, bool)), "Transfer failed"


@internal 
def _safe_transfer_eth(_to: address, _amount: uint256):
    success: bool = raw_call(_to, b"", value=_amount, revert_on_failure=False)
    assert success, "ETH transfer failed"


@view 
@external 
def pools_length() -> uint256:
    return len(self.pools)

#######################################################
#                 Fee manager read functions
#######################################################

@view
@external 
def get_swap_fee(_pool: address, _sender: address, _token_in: address, _token_out: address, _data: Bytes[1_024]) -> uint24:
    fee: uint24 = self.token_swap_fee[_token_in][_token_out]

    if fee == 0:
        fee = self.default_swap_fee[staticcall IPool(_pool).pool_type()]
    else:
        if fee == ZERO_CUSTOM_FEE:
            fee = 0

    return fee


@view 
@external 
def get_protocol_fee(_pool: address) -> uint24:
    fee: uint24 = self.pool_protocol_fee[_pool]

    if fee == 0:
        fee = self.default_protocol_fee[staticcall IPool(_pool).pool_type()]
    else:
        if fee == ZERO_CUSTOM_FEE:
            fee = 0
    
    return fee


@view 
@external 
def get_fee_recipient() -> address:
    return self.fee_recipient


@view 
@internal 
def _is_fee_sender(_sender: address) -> bool:
    return self.is_sender_whitelisted[_sender] or self.is_pool[_sender]


@view 
@external 
def is_fee_sender(_sender: address) -> bool:
    return self._is_fee_sender(_sender)


@view 
@external 
def fee_tokens_length(_epoch: uint256) -> uint256:
    return len(self.fee_tokens[_epoch])


@view 
@external 
def fee_distributors_length() -> uint256:
    return len(self.fee_distributors)


@view 
@internal 
def _get_epoch_start(_ts: uint256) -> uint256:
    return _ts - (_ts // self.epoch_duration)


#######################################################
#                 Fee manager write functions
#######################################################

@external 
def notify_fees(_fee_type: uint16, _token: address, _amount: uint256, _fee_rate: uint256, _data: Bytes[1_024]):
    assert self._is_fee_sender(msg.sender), "Invalid fee sender"

    epoch: uint256 = self._get_epoch_start(block.timestamp)
    epoch_token_fees: uint256 = self.fees[epoch][_token]

    if epoch_token_fees == 0:
        self.fee_tokens[epoch].append(_token)
        self.fees[epoch][_token] = _amount
        self.fee_token_data[msg.sender][_token] = FeeTokenData(start_time=block.timestamp, amount=_amount)
    else:
        self.fees[epoch][_token] = epoch_token_fees + _amount
        self.fee_token_data[msg.sender][_token].amount += _amount

    log NotifyFees(msg.sender, _fee_type, _token, _amount, _fee_rate)


@external
def distribute_fees(_to: address, _tokens: DynArray[address, max_value(uint8)], _amounts: DynArray[uint256, max_value(uint8)]):
    assert self.is_fee_distributor[msg.sender] or msg.sender == self.owner, "No perms"
    assert len(_tokens) == len(_amounts), "Wrong length"

    n: uint256 = len(_tokens)
    token: address = empty(address)
    amount: uint256 = empty(uint256)

    for i: uint256 in range(255):
        if i >= n:
            break

        token = _tokens[i]
        amount = _amounts[i]

        if token == empty(address):
            if amount == 0:
                amount = self.balance 
            self._safe_transfer_eth(_to, amount)
        else:
            if amount == 0:
                amount = staticcall IERC20(token).balanceOf(self)
            self._safe_transfer(token, _to, amount)


@external
def add_fee_distributor(_distributor: address):
    assert msg.sender == self.owner, "Only owner"
    assert _distributor != empty(address), "Invalid address"
    assert not self.is_fee_distributor[_distributor], "Already set"

    self.is_fee_distributor[_distributor] = True
    self.fee_distributors.append(_distributor)
    log AddFeeDistributor(_distributor)


@external
def remove_fee_distributor(_distributor: address, _update_array: bool):
    assert msg.sender == self.owner, "Only owner"
    assert self.is_fee_distributor[_distributor], "No set"
    
    self.is_fee_distributor[_distributor] = False
    if _update_array:
        n: uint256 = len(self.fee_distributors)
        for i: uint256 in range(255):
            if i >= n:
                break
            if self.fee_distributors[i] == _distributor:
                self.fee_distributors[i] = self.fee_distributors[n-1]
                self.fee_distributors[n-1] = _distributor
                self.fee_distributors.pop()
                break

    log RemoveFeeDistributor(_distributor)


@external
def set_epoch_duration(_epoch_duration: uint256):
    assert msg.sender == self.owner, "Only owner"

    self.epoch_duration = _epoch_duration
    log SetEpochDuration(_epoch_duration)


@external
def withdraw_erc20(_token: address, _to: address, _amount: uint256):
    assert msg.sender == self.owner, "Only owner"
    
    amount: uint256 = _amount
    if amount == 0:
        amount = staticcall IERC20(_token).balanceOf(self)
    self._safe_transfer(_token, _to, amount)


@external
def withdraw_eth(_to: address, _amount: uint256):
    assert msg.sender == self.owner, "Only owner"

    amount: uint256 = _amount
    if _amount == 0:
        amount = self.balance
    self._safe_transfer_eth(_to, amount)


@external 
def set_default_swap_fee(_pool_type: uint16, _fee: uint24):
    assert msg.sender == self.owner, "Only owner"
    assert _fee == ZERO_CUSTOM_FEE or _fee <= MAX_SWAP_FEE, "Invalid fee"

    self.default_swap_fee[_pool_type] = _fee
    log SetDefaultSwapFee(_pool_type, _fee)


@external 
def set_token_swap_fee(_token_in: address, _token_out: address, _fee: uint24):
    assert msg.sender == self.owner, "Only owner"
    assert _fee == ZERO_CUSTOM_FEE or _fee <= MAX_SWAP_FEE, "Invalid fee"

    self.token_swap_fee[_token_in][_token_out] = _fee
    log SetTokenSwapFee(_token_in, _token_out, _fee)


@external 
def set_default_protocol_fee(_pool_type: uint16, _fee: uint24):
    assert msg.sender == self.owner, "Only owner"
    assert _fee == ZERO_CUSTOM_FEE or _fee <= MAX_SWAP_FEE, "Invalid fee"

    self.default_protocol_fee[_pool_type] = _fee
    log SetDefaultProtocolFee(_pool_type, _fee)


@external 
def set_pool_protocol_fee(_pool: address, _fee: uint24):
    assert msg.sender == self.owner, "Only owner"
    assert _fee == ZERO_CUSTOM_FEE or _fee <= MAX_SWAP_FEE, "Invalid fee"

    self.pool_protocol_fee[_pool] = _fee
    log SetPoolProtocolFee(_pool, _fee)


@external 
def set_fee_recipient(_fee_recipient: address):
    assert msg.sender == self.owner, "Only owner"
    log SetFeeRecipient(self.fee_recipient, _fee_recipient)
    self.fee_recipient = _fee_recipient


@external 
def set_sender_whitelisted(_sender: address, _is_whitelisted: bool):
    assert msg.sender == self.owner, "Only owner"
    assert _sender != empty(address), "Invalid address"
    assert self.is_sender_whitelisted[_sender] != _is_whitelisted, "Already set"

    self.is_sender_whitelisted[_sender] = _is_whitelisted
    log SetSenderWhitelisted(_sender, _is_whitelisted)


#######################################################
#                 pool master write functions
#######################################################

@external 
def add_forwarder(_forwarder: address):
    assert msg.sender == self.owner, "Only owner"
    assert _forwarder != empty(address), "Invalid address"
    assert not self.is_forwarder[_forwarder], "Already added"

    self.is_forwarder[_forwarder] = True
    log AddForwarder(_forwarder)


@external 
def remove_forwarder(_forwarder: address):
    assert msg.sender == self.owner, "Invalid address"
    self.is_forwarder[_forwarder] = False

    log RemoveForwarder(_forwarder)


@external 
def set_factory_whitelisted(_factory: address, _whitelisted: bool):
    assert msg.sender == self.owner, "Invalid address"
    assert _factory != empty(address), "Invalid factory"

    self.is_factory_whitelisted[_factory] = _whitelisted
    log SetFactoryWhitelisted(_factory, _whitelisted)


@external 
def create_pool(_factory: address, _data: Bytes[1_024]) -> address:
    return extcall IPoolFactory(_factory).create_pool(_data)


@external 
def register_pool(_pool: address, _pool_type: uint16, _data: Bytes[1_024]):
    assert self.is_factory_whitelisted[msg.sender], "Not Whitelisted Factory"
    assert _pool != empty(address), "Invalid pool"
    assert not self.is_pool[_pool], "Pool Already Exists"

    data_hash: bytes32 = keccak256(abi_encode(_pool_type, _data))

    assert self.get_pool[data_hash] == empty(address), "Pool Already Exists"

    self.get_pool[data_hash] = _pool
    self.is_pool[_pool] = True
    self.pools.append(_pool)

    log RegisterPool(msg.sender, _pool, _pool_type, _data)
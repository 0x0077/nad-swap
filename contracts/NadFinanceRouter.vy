#pragma version 0.4.0

from ethereum.ercs import IERC20

interface IVault:
    def wETH() -> address: view
    def reserves(_token: address) -> uint256: view
    def balanceOf(_token: address, _owner: address) -> uint256: view
    def deposit(_token: address, _to: address) -> uint256: payable
    def deposit_eth(_to: address) -> uint256: payable
    def transfer_and_deposit(_token: address, _to: address, _amount: uint256) -> uint256: payable
    def transfer(_token: address, _to: address, _amount: uint256): nonpayable
    def withdraw(_token: address, _to: address, _amount: uint256): nonpayable
    def withdraw_alternative(_token: address, _to: address, _amount: uint256, _mode: uint8): nonpayable
    def withdraw_eth(_to: address, _amount: uint256): nonpayable

interface IPool:
    def mint(_data: Bytes[65], _sender: address, _callback: address, _callback_data: Bytes[1_024]) -> uint256: nonpayable
    def burn(_data: Bytes[1_024], _sender: address, _callback: address, _callback_data: Bytes[1_024]) -> DynArray[TokenAmount, 2]: nonpayable
    def burn_single(_data: Bytes[1_024], _sender: address, _callback: address, _callback_data: Bytes[1_024]) -> TokenAmount: nonpayable
    def swap(_data: Bytes[1_024], _sender: address, _callback: address, _callback_data: Bytes[1_024]) -> TokenAmount: nonpayable
    def permit(
        _owner: address,
        _spender: address,
        _value: uint256,
        _deadline: uint256,
        _v: uint8,
        _r: bytes32,
        _s: bytes32
    ): nonpayable
    def permit2(_owner: address, _spender: address, _amount: uint256, _deadline: uint256, _signature: Bytes[1_024]): nonpayable

interface IPoolFactory:
    def create_pool(_data: Bytes[1_024]) -> address: nonpayable

interface IStakingPool:
    def stake(_amount: uint256, _on_behalf: address): nonpayable

struct TokenInput:
    token: address
    amount: uint256

struct TokenAmount:
    token: address
    amount: uint256

struct SwapStep:
    pool: address
    data: Bytes[1_024]
    callback: address
    callback_data: Bytes[1_024]

struct SwapPath:
    steps: DynArray[SwapStep, MAX_PATHS]
    token_in: address
    amount_in: uint256

struct SplitPermitParams:
    token: address
    approve_amount: uint256
    deadline: uint256
    v: uint8
    r: bytes32
    s: bytes32

struct ArrayPermitParams:
    approve_amount: uint256
    deadline: uint256
    signature: Bytes[65]

MAX_PATHS: constant(uint256) = 5
NATIVE_ETH: constant(address) = empty(address)
vault: public(immutable(address))
wETH: public(immutable(address))

is_pool_entered: public(HashMap[address, HashMap[address, bool]])
entered_pools: public(HashMap[address, DynArray[address, max_value(uint16)]])


@deploy 
@payable 
def __init__(_vault: address, _weth: address):
    vault = _vault
    wETH = _weth


@view 
@internal 
def _ensure(_deadline: uint256):
    assert block.timestamp <= _deadline, "Expired"


@internal 
def _safe_approve(_token: address, _to: address, _amount: uint256):
    response: Bytes[32] = b""
    success: bool = False
    success, response = raw_call(
        _token,
        abi_encode(
            _to,
            _amount,
            method_id=method_id("approve(address,uint256)")
        ),
        max_outsize=32,
        revert_on_failure=False
    )

    assert success and (len(response) > 0 and convert(response, bool)), "Transfer failed"


@internal 
def _safe_transfer_from(_token: address, _from: address, _to: address, _amount: uint256):
    response: Bytes[32] = b""
    success: bool = False
    success, response = raw_call(
        _token,
        abi_encode(
            _from,
            _to,
            _amount,
            method_id=method_id("transferFrom(address,address,uint256)")
        ),
        max_outsize=32,
        revert_on_failure=False
    )

    assert success and (len(response) > 0 and convert(response, bool)), "Transfer failed"


@internal 
def _transfer_from_sender(_sender: address, _token: address, _to: address, _amount: uint256):
    if _token == NATIVE_ETH:
        extcall IVault(vault).deposit(_token, _to, value=_amount)
    else:
        self._safe_transfer_from(_token, _sender, vault, _amount)
        extcall IVault(vault).deposit(_token, _to)


@internal 
def _transfer_and_add_liquidity(
    _sender: address,
    _pool: address,
    _inputs: DynArray[TokenInput, max_value(uint8)],
    _data: Bytes[65],
    _min_liquidity: uint256,
    _callback: address,
    _callback_data: Bytes[1_024]
) -> uint256:
    n: uint256 = len(_inputs)

    _input: TokenInput = empty(TokenInput)

    for i: uint256 in range(2):
        if i >= n:
            break
        _input = _inputs[i]
        self._transfer_from_sender(_sender, _input.token, _pool, _input.amount)
    
    liquidity: uint256 = extcall IPool(_pool).mint(_data, _sender, _callback, _callback_data)
    assert liquidity >= _min_liquidity, "Not Enough Liquidity Minted"

    return liquidity


@internal 
def _transfer_and_burn_liquidity(
    _sender: address,
    _pool: address,
    _liquidity: uint256,
    _data: Bytes[1_024],
    _min_amounts: DynArray[uint256, max_value(uint8)],
    _callback: address,
    _callback_data: Bytes[1_024]
) -> DynArray[TokenAmount, max_value(uint8)]:

    extcall IERC20(_pool).transferFrom(_sender, _pool, _liquidity)

    amounts: DynArray[TokenAmount, max_value(uint8)] = extcall IPool(_pool).burn(_data, _sender, _callback, _callback_data)
    n: uint256 = len(amounts)

    for i: uint256 in range(255):
        if i >= n:
            break
        assert amounts[i].amount >= _min_amounts[i], "Too Little Received"
    
    return amounts


@internal 
def _transfer_and_burn_liquidity_single(
    _sender: address,
    _pool: address,
    _liquidity: uint256,
    _data: Bytes[1_024],
    _min_amount: uint256,
    _callback: address,
    _callback_data: Bytes[1_024]
) -> TokenAmount:

    extcall IERC20(_pool).transferFrom(_sender, _pool, _liquidity)
    amount_out: TokenAmount = extcall IPool(_pool).burn_single(_data, _sender, _callback, _callback_data)
    
    assert amount_out.amount >= _min_amount, "Too Little Received"
    return amount_out


@internal 
def _swap(_sender: address, _paths: DynArray[SwapPath, MAX_PATHS], _amount_out_min: uint256) -> TokenAmount:
    paths_length: uint256 = len(_paths)
    path: SwapPath = empty(SwapPath)
    step: SwapStep = empty(SwapStep)
    token_amount: TokenAmount = empty(TokenAmount)
    amount_out: TokenAmount = empty(TokenAmount)
    steps_length: uint256 = empty(uint256)
    # x: uint256 = empty(uint256)

    for i: uint256 in range(MAX_PATHS):
        if i >= paths_length:
            break
        
        path = _paths[i]
        step = path.steps[0]
        self._transfer_from_sender(_sender, path.token_in, step.pool, path.amount_in)

        steps_length = len(path.steps)

        for j: uint256 in range(MAX_PATHS):
            if j >= steps_length:
                break
            
            if j == steps_length - 1:
                token_amount = extcall IPool(step.pool).swap(step.data, _sender, step.callback, step.callback_data)
                amount_out.token = token_amount.token
                amount_out.amount += token_amount.amount
                break
            else:
                extcall IPool(step.pool).swap(step.data, _sender, step.callback, step.callback_data)
                step = path.steps[j+1]

    assert amount_out.amount >= _amount_out_min, "Too Little Received"

    return amount_out


@internal 
def _mark_pool_entered(_sender: address, _pool: address):
    if not self.is_pool_entered[_pool][_sender]:
        self.is_pool_entered[_pool][_sender] = True
        self.entered_pools[_sender].append(_pool)


@view 
@external
def entered_pools_length(_account: address) -> uint256:
    return len(self.entered_pools[_account])


@payable 
@external 
def add_liquidity(
    _pool: address,
    _inputs: DynArray[TokenInput, max_value(uint8)],
    _data: Bytes[65],
    _min_liquidity: uint256,
    _callback: address,
    _callback_data: Bytes[1_024]
) -> uint256:
    return self._transfer_and_add_liquidity(
        msg.sender,
        _pool,
        _inputs,
        _data,
        _min_liquidity,
        _callback,
        _callback_data
    )

    
@payable 
@external 
def add_liquidity2(
    _pool: address,
    _inputs: DynArray[TokenInput, max_value(uint8)],
    _data: Bytes[65],
    _min_liquidity: uint256,
    _callback: address,
    _callback_data: Bytes[1_024]
) -> uint256:
    liquidity: uint256 = self._transfer_and_add_liquidity(
        msg.sender,
        _pool,
        _inputs,
        _data,
        _min_liquidity,
        _callback,
        _callback_data
    )

    self._mark_pool_entered(msg.sender, _pool)

    return liquidity


@payable 
@external 
def add_liquidity_with_permit(
    _pool: address,
    _inputs: DynArray[TokenInput, max_value(uint8)],
    _data: Bytes[65],
    _min_liquidity: uint256,
    _callback: address,
    _callback_data: Bytes[1_024],
    _permits: DynArray[SplitPermitParams, max_value(uint8)]
) -> uint256:
    n: uint256 = len(_permits)
    params: SplitPermitParams = empty(SplitPermitParams)

    for i: uint256 in range(255):
        if i >= n:
            break
        
        params = _permits[i]
        
        extcall IPool(params.token).permit(
            msg.sender,
            self,
            params.approve_amount,
            params.deadline,
            params.v,
            params.r,
            params.s
        )

    liquidity: uint256 = self._transfer_and_add_liquidity(
        msg.sender,
        _pool,
        _inputs,
        _data,
        _min_liquidity,
        _callback,
        _callback_data
    )

    return liquidity


@payable 
@external 
def add_liquidity_with_permit2(
    _pool: address,
    _inputs: DynArray[TokenInput, max_value(uint8)],
    _data: Bytes[65],
    _min_liquidity: uint256,
    _callback: address,
    _callback_data: Bytes[1_024],
    _permits: DynArray[SplitPermitParams, max_value(uint8)]
) -> uint256:
    n: uint256 = len(_permits)
    params: SplitPermitParams = empty(SplitPermitParams)

    for i: uint256 in range(255):
        if i >= n:
            break
        
        params = _permits[i]
        
        extcall IPool(params.token).permit(
            msg.sender,
            self,
            params.approve_amount,
            params.deadline,
            params.v,
            params.r,
            params.s
        )

    liquidity: uint256 = self._transfer_and_add_liquidity(
        msg.sender,
        _pool,
        _inputs,
        _data,
        _min_liquidity,
        _callback,
        _callback_data
    )

    self._mark_pool_entered(msg.sender, _pool)

    return liquidity


@external 
def burn_liquidity(
    _pool: address,
    _liquidity: uint256,
    _data: Bytes[1_024],
    _min_amounts: DynArray[uint256, max_value(uint8)],
    _callback: address,
    _callback_data: Bytes[1_024]
) -> DynArray[TokenAmount, max_value(uint8)]:
    return self._transfer_and_burn_liquidity(
        msg.sender,
        _pool,
        _liquidity,
        _data,
        _min_amounts,
        _callback,
        _callback_data
    )


@external 
def burn_liquidity_with_permit(
    _pool: address,
    _liquidity: uint256,
    _data: Bytes[1_024],
    _min_amounts: DynArray[uint256, max_value(uint8)],
    _callback: address,
    _callback_data: Bytes[1_024],
    _permit: ArrayPermitParams
) -> DynArray[TokenAmount, max_value(uint8)]:
    extcall IPool(_pool).permit2(
        msg.sender,
        self,
        _permit.approve_amount,
        _permit.deadline,
        _permit.signature
    )

    return self._transfer_and_burn_liquidity(
        msg.sender,
        _pool,
        _liquidity,
        _data,
        _min_amounts,
        _callback,
        _callback_data
    )


@external 
def burn_liquidity_single(
    _pool: address,
    _liquidity: uint256,
    _data: Bytes[1_024],
    _min_amount: uint256,
    _callback: address,
    _callback_data: Bytes[1_024]
) -> TokenAmount:
    return self._transfer_and_burn_liquidity_single(
        msg.sender,
        _pool,
        _liquidity,
        _data,
        _min_amount,
        _callback,
        _callback_data
    )


@external 
def burn_liquidity_single_with_permit(
    _pool: address,
    _liquidity: uint256,
    _data: Bytes[1_024],
    _min_amount: uint256,
    _callback: address,
    _callback_data: Bytes[1_024],
    _permit: ArrayPermitParams
) -> TokenAmount:
    extcall IPool(_pool).permit2(
        msg.sender,
        self,
        _permit.approve_amount,
        _permit.deadline,
        _permit.signature
    )
    return self._transfer_and_burn_liquidity_single(
        msg.sender,
        _pool,
        _liquidity,
        _data,
        _min_amount,
        _callback,
        _callback_data
    )


@payable 
@external 
def swap(_paths: DynArray[SwapPath, MAX_PATHS], _amount_out_min: uint256, _deadline: uint256) -> TokenAmount:
    self._ensure(_deadline)

    return self._swap(
        msg.sender,
        _paths,
        _amount_out_min
    )


@payable 
@external 
def swap_with_permit(_paths: DynArray[SwapPath, MAX_PATHS], _amount_out_min: uint256, _deadline: uint256, _permit: SplitPermitParams) -> TokenAmount:
    extcall IPool(_permit.token).permit(
        msg.sender,
        self,
        _permit.approve_amount,
        _permit.deadline,
        _permit.v,
        _permit.r,
        _permit.s
    )

    return self._swap(
        msg.sender,
        _paths,
        _amount_out_min
    )


@payable 
@external 
def create_pool(_factory: address, _data: Bytes[1_024]) -> address:
    return extcall IPoolFactory(_factory).create_pool(_data)


@external 
def stake(_staking_pool: address, _token: address, _amount: uint256, _on_behalf: address):
    self._safe_transfer_from(_token, msg.sender, self, _amount)

    if staticcall IERC20(_token).allowance(self, _staking_pool) < _amount:
        self._safe_approve(_token, _staking_pool, max_value(uint256))

    extcall IStakingPool(_staking_pool).stake(_amount, _on_behalf)
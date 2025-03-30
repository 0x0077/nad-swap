# NadSwap

NadSwap is an efficient and secure decentralized exchange protocol. It features both stable and crypto pool implementations, optimized for different trading scenarios.

## Overview

NadSwap is built with a focus on:
- Gas efficiency through Vyper implementation
- Stable and volatile asset trading pairs
- Advanced routing capabilities
- Secure vault management
- Factory pattern for pool deployment

## Core Components

### Router (`NadFinanceRouter.vy`)
- Handles trade routing and execution
- Manages multi-hop swaps
- Provides liquidity management functions

### Vault (`NadFinanceVault.vy`)
- Secure token custody
- Manages pool assets
- Handles deposit and withdrawal operations

### Pool Master (`NadFinancePoolMaster.vy`)
- Central pool management
- Coordinates pool operations
- Implements core AMM logic

### Pool Types

#### Stable Pools (`NadFinanceStablePool.vy`)
- Optimized for stable asset pairs
- Lower slippage for similar-valued assets
- Ideal for stablecoin trading

#### Crypto Pools (`NadFinanceCryptoPool.vy`)
- Designed for volatile asset pairs
- Standard AMM curve
- Suitable for general cryptocurrency trading

### Factories
- `NadFinanceStablePoolFactory.vy`: Deploys stable pools
- `NadFinanceCryptoPoolFactory.vy`: Deploys crypto pools

## Development Setup

### Prerequisites
- Python 3.7+
- [Vyper](https://vyper.readthedocs.io/)
- [Ape Framework](https://docs.apeworx.io/)

### Installation
```bash
# Install dependencies
pip install -r requirements.txt
```

### Testing
```bash
# Run tests
ape test
```

## Security

The protocol implements various security measures:
- Reentrancy protection
- Overflow/underflow checks (built into Vyper)
- Access control mechanisms
- Secure math operations

## License

[License Type] - See LICENSE file for details

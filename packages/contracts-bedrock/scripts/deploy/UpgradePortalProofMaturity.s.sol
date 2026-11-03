// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { DeployUtils } from "scripts/libraries/DeployUtils.sol";
import { IOptimismPortal2 } from "interfaces/L1/IOptimismPortal2.sol";
import { IProxyAdmin } from "interfaces/universal/IProxyAdmin.sol";

/// @title UpgradePortalProofMaturity
/// @notice Changes `PROOF_MATURITY_DELAY_SECONDS` of a live OptimismPortal2.
///
///         The delay is an immutable of the implementation, so the only way to change it is to
///         deploy a new implementation (same source, different constructor arg) and point the
///         portal proxy at it via `ProxyAdmin.upgrade`. `upgradeAndCall` must NOT be used: the
///         proxy is already initialized at `initVersion()` and `initialize` would revert. Proxy
///         storage is untouched by the upgrade.
///
///         Entry points:
///         - `deploy(delay)`: broadcast the new implementation.
///         - `check(portal, impl, delay)`: simulate the upgrade on a fork as the ProxyAdmin owner,
///           assert that only the implementation and the delay change, and print the Safe tx.
///         - `run(portal, delay)`: `deploy` + `check` in one go, for a dry run on a fork.
///
///         Note: the delay is compared against already-proven withdrawals at finalization time,
///         so the change applies retroactively to every pending withdrawal.
contract UpgradePortalProofMaturity is Script {
    /// @notice EIP-1967 admin slot, bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1).
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice Getters that must be identical before and after the upgrade.
    struct PortalState {
        string version;
        uint8 initVersion;
        address systemConfig;
        address anchorStateRegistry;
        address disputeGameFactory;
        address superchainConfig;
        address ethLockbox;
        address l2Sender;
        address guardian;
        bool paused;
        uint128 prevBaseFee;
        uint64 prevBoughtGas;
        uint64 prevBlockNum;
        uint256 disputeGameFinalityDelaySeconds;
        uint32 respectedGameType;
        uint256 balance;
    }

    /// @notice Deploys a new OptimismPortal2 implementation with the given delay.
    function deploy(uint256 _delay) public returns (address impl_) {
        require(_delay != 0, "UPPM-10: delay must be non-zero");

        vm.broadcast();
        impl_ = DeployUtils.create1("OptimismPortal2.sol:OptimismPortal2", abi.encode(_delay));

        require(IOptimismPortal2(payable(impl_)).proofMaturityDelaySeconds() == _delay, "UPPM-20: delay mismatch");
        console.log("New OptimismPortal2 implementation:", impl_);
    }

    /// @notice Simulates `ProxyAdmin.upgrade(_portal, _impl)` and prints the Safe transaction.
    function check(address payable _portal, address _impl, uint256 _delay) public {
        IOptimismPortal2 portal = IOptimismPortal2(_portal);
        IProxyAdmin proxyAdmin = IProxyAdmin(address(uint160(uint256(vm.load(_portal, ADMIN_SLOT)))));
        address owner = proxyAdmin.owner();
        address oldImpl = proxyAdmin.getProxyImplementation(_portal);

        // The new implementation must be the same contract version as the live one, otherwise
        // this is not a parameter change but a contract upgrade and needs a different review.
        IOptimismPortal2 impl = IOptimismPortal2(payable(_impl));
        require(_impl.code.length > 0, "UPPM-30: impl has no code");
        require(_impl != oldImpl, "UPPM-40: impl already set");
        require(impl.proofMaturityDelaySeconds() == _delay, "UPPM-50: impl delay mismatch");
        require(_eq(impl.version(), portal.version()), "UPPM-60: impl version differs from live");
        require(impl.initVersion() == portal.initVersion(), "UPPM-70: impl initVersion differs from live");

        uint256 oldDelay = portal.proofMaturityDelaySeconds();
        PortalState memory pre = _snapshot(portal);

        bytes memory data = abi.encodeCall(IProxyAdmin.upgrade, (_portal, _impl));
        vm.prank(owner);
        (bool ok, bytes memory ret) = address(proxyAdmin).call(data);
        require(ok, string(ret));

        require(proxyAdmin.getProxyImplementation(_portal) == _impl, "UPPM-80: impl not set");
        require(portal.proofMaturityDelaySeconds() == _delay, "UPPM-90: delay not applied");
        require(keccak256(abi.encode(_snapshot(portal))) == keccak256(abi.encode(pre)), "UPPM-100: state changed");

        console.log("Portal proxy:      ", _portal);
        console.log("ProxyAdmin:        ", address(proxyAdmin));
        console.log("ProxyAdmin owner:  ", owner);
        console.log("Old implementation:", oldImpl);
        console.log("New implementation:", _impl);
        console.log("Old delay (s):     ", oldDelay);
        console.log("New delay (s):     ", _delay);
        console.log("");
        console.log("Safe transaction (from ProxyAdmin owner):");
        console.log("  to:   ", address(proxyAdmin));
        console.log("  value: 0");
        console.log("  data: ");
        console.logBytes(data);
        console.log("");
        console.log("Rollback data (upgrade back to old implementation):");
        console.logBytes(abi.encodeCall(IProxyAdmin.upgrade, (_portal, oldImpl)));
    }

    /// @notice Dry run: deploy on the fork, then check. Run without --broadcast.
    function run(address payable _portal, uint256 _delay) public {
        check(_portal, deploy(_delay), _delay);
    }

    function _snapshot(IOptimismPortal2 _portal) internal view returns (PortalState memory s_) {
        s_.version = _portal.version();
        s_.initVersion = _portal.initVersion();
        s_.systemConfig = address(_portal.systemConfig());
        s_.anchorStateRegistry = address(_portal.anchorStateRegistry());
        s_.disputeGameFactory = address(_portal.disputeGameFactory());
        s_.superchainConfig = address(_portal.superchainConfig());
        s_.ethLockbox = address(_portal.ethLockbox());
        s_.l2Sender = _portal.l2Sender();
        s_.guardian = _portal.guardian();
        s_.paused = _portal.paused();
        (s_.prevBaseFee, s_.prevBoughtGas, s_.prevBlockNum) = _portal.params();
        s_.disputeGameFinalityDelaySeconds = _portal.disputeGameFinalityDelaySeconds();
        s_.respectedGameType = _portal.respectedGameType().raw();
        s_.balance = address(_portal).balance;
    }

    function _eq(string memory _a, string memory _b) internal pure returns (bool) {
        return keccak256(bytes(_a)) == keccak256(bytes(_b));
    }
}

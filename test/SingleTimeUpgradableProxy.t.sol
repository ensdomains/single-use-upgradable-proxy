// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts-sup/interfaces/IERC1967.sol";
import "../src/SingleTimeUpgradableProxy.sol";
import "../src/mocks/MockUniversalV1.sol";
import "../src/mocks/MockUniversalV2.sol";

contract ProxyTest is Test {
    address constant ADMIN = address(0x123);
    address constant USER = address(0x456);
    address constant STRANGER = address(0x789);
    
    SingleTimeUpgradableProxy proxy;
    MockUniversalV1 v1;
    MockUniversalV2 v2;
    MockUniversalV2 v2Bad;
    
    function setUp() public {
        vm.startPrank(ADMIN);
        v1 = new MockUniversalV1();
        v2 = new MockUniversalV2();
        v2Bad = new MockUniversalV2();
        
        // For the basic mock tests, we don't need initialization data
        proxy = new SingleTimeUpgradableProxy(ADMIN, address(v1), "");
        vm.stopPrank();
    }
    
    /////// Core Functionality Tests ///////
    function test_InitialState() public view {
        assertEq(proxy.admin(), ADMIN);
        assertEq(proxy.implementation(), address(v1));
        
        // When using a CALL-based proxy, the owner is not set through initialization
        MockUniversalV1 proxyV1 = MockUniversalV1(address(proxy));
        assertEq(proxyV1.owner(), ADMIN);
    }
    
    function test_ProxyFunctionality() public {
        MockUniversalV1 proxyV1 = MockUniversalV1(address(proxy));
        
        vm.prank(ADMIN);
        proxyV1.setValue(100);
        
        // With CALL-based proxy, state is stored in implementation
        assertEq(proxyV1.value(), 100);
        assertEq(v1.value(), 100);
    }
    
    /////// Upgrade Tests ///////
    function test_SuccessfulUpgrade() public {
        vm.prank(ADMIN);
        proxy.upgradeToAndCall(address(v2), "");
        
        assertEq(proxy.implementation(), address(v2));
        assertEq(proxy.admin(), address(0));
        
        MockUniversalV2 upgraded = MockUniversalV2(address(proxy));
        
        vm.prank(USER);
        upgraded.setSecondValue(200);
        
        // State stored in implementation
        assertEq(upgraded.secondValue(), 200);
        assertEq(v2.secondValue(), 200);
    }
    
    function test_StorageIndependenceAfterUpgrade() public {
        // Create a new proxy for this test
        SingleTimeUpgradableProxy proxyTemp = new SingleTimeUpgradableProxy(ADMIN, address(v1), "");
        MockUniversalV1 proxyV1 = MockUniversalV1(address(proxyTemp));
        
        // Set value in first implementation
        vm.prank(USER);
        proxyV1.setValue(100);
        
        // Verify state is stored in implementation
        assertEq(proxyV1.value(), 100);
        assertEq(v1.value(), 100);
        
        // Upgrade to v2
        vm.prank(ADMIN);
        proxyTemp.upgradeToAndCall(address(v2), "");
        
        // Check if the storage is independent (new implementation starts with fresh state)
        MockUniversalV2 proxyV2 = MockUniversalV2(address(proxyTemp));
        
        // With CALL-based proxy, storage is independent
        // v2 has its own storage, separate from v1
        assertEq(proxyV2.value(), 0);
        
        // v1 implementation still has its original value
        assertEq(v1.value(), 100);
    }
    
    /////// Security Tests ///////
    function test_RevertIf_NonAdminUpgrade() public {
        vm.prank(STRANGER);
        vm.expectRevert(SingleTimeUpgradableProxy.CallerNotAdmin.selector);
        proxy.upgradeToAndCall(address(v2), "");
    }
    
    function test_RevertIf_DoubleUpgrade() public {
        vm.startPrank(ADMIN);
        proxy.upgradeToAndCall(address(v2), "");
        vm.expectRevert(SingleTimeUpgradableProxy.CallerNotAdmin.selector);
        proxy.upgradeToAndCall(address(v2Bad), "");
    }
    
    function test_RevertIf_SameImplementation() public {
        vm.prank(ADMIN);
        vm.expectRevert(SingleTimeUpgradableProxy.SameImplementation.selector);
        proxy.upgradeToAndCall(address(v1), "");
    }
    
    function test_RevertIf_NonContractUpgrade() public {
        vm.prank(ADMIN);
        vm.expectRevert(SingleTimeUpgradableProxy.InvalidImplementation.selector);
        proxy.upgradeToAndCall(STRANGER, "");
    }
    
    function test_UpgradeEmitsEvents() public {
        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(v2));
        
        vm.expectEmit(true, true, true, true);
        emit UpgradeRevoked(ADMIN);
        
        vm.prank(ADMIN);
        proxy.upgradeToAndCall(address(v2), "");
    }
    
    /////// Edge Cases ///////
    function test_AdminRevocationAfterUpgrade() public {
        vm.prank(ADMIN);
        proxy.upgradeToAndCall(address(v2), "");
        
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        address currentAdmin = address(uint160(uint256(vm.load(address(proxy), adminSlot))));
        assertEq(currentAdmin, address(0));
    }
    
    function test_InitializationWithData() public {
        // Test constructor initialization with data
        bytes memory initData = abi.encodeWithSelector(MockUniversalV1.setValue.selector, 42);
        SingleTimeUpgradableProxy proxyWithInit = new SingleTimeUpgradableProxy(ADMIN, address(v1), initData);
        
        MockUniversalV1 init = MockUniversalV1(address(proxyWithInit));
        assertEq(init.value(), 42);
        
        // Test upgrade with initialization data
        bytes memory upgradeData = abi.encodeWithSelector(MockUniversalV2.setSecondValue.selector, 84);
        
        vm.prank(ADMIN);
        proxyWithInit.upgradeToAndCall(address(v2), upgradeData);
        
        MockUniversalV2 upgraded = MockUniversalV2(address(proxyWithInit));
        assertEq(upgraded.secondValue(), 84);
    }
}

// These event definitions match what's in the proxy
event Upgraded(address indexed implementation);
event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
event UpgradeRevoked(address indexed admin);
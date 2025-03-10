// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SingleTimeUpgradableProxy.sol";

import {UniversalResolver as UniversalResolverV1} from "../src/mocks/UniversalResolverV1.sol";
import {UniversalResolver as UniversalResolverV3} from "../src/mocks/UniversalResolverV3.sol";
import {UR} from "@unruggable-labs/contracts/UR.sol";
import {ReverseUR} from "@unruggable-labs/contracts/ReverseUR.sol";

import {ENS} from "@ens-contracts-urv3/contracts/registry/ENS.sol";

contract ProxyTest is Test {
    address constant ADMIN = address(0x123);
    address constant USER = address(0x456);
    address constant STRANGER = address(0x789);

    SingleTimeUpgradableProxy proxy;
    UniversalResolverV1 urV1;
    UniversalResolverV3 urV3;

    UR ur;
    ReverseUR reverseUR;

    ENS ens = ENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);

    function setUp() public {
        string[] memory urls = new string[](1);
        urls[0] = "http://universal-offchain-resolver.local";

        vm.startPrank(ADMIN);
        ur = new UR(address(ens), urls);
        reverseUR = new ReverseUR(ur);

        urV1 = new UniversalResolverV1(address(ens), urls);
        urV3 = new UniversalResolverV3(reverseUR);
        
        proxy = new SingleTimeUpgradableProxy(ADMIN, address(urV1), "");

        urV1.transferOwnership(address(proxy));
        vm.stopPrank();
    }

    /////// Core Functionality Tests ///////
    function test_InitialState() public view {
        assertEq(proxy.admin(), ADMIN);
        assertEq(proxy.implementation(), address(urV1));

        UniversalResolverV1 proxyV1 = UniversalResolverV1(address(proxy));
        console.log("proxyV1.owner()");
        console.logAddress(proxyV1.owner());
        assertEq(proxyV1.owner(), address(proxy));
    }

    function test_ProxyFunctionality() public {
        UniversalResolverV1 proxyV1 = UniversalResolverV1(address(proxy));

        string[] memory urls = new string[](1);
        urls[0] = "https://test1";
        vm.prank(ADMIN);  // Use ADMIN instead of proxyV1.owner()
        proxyV1.setGatewayURLs(urls);

        assertEq(proxyV1.batchGatewayURLs(0), urls[0]);
    }

    /////// Upgrade Tests ///////
    function test_SuccessfulUpgradeToV3() public {
        vm.prank(ADMIN);
        proxy.upgradeToAndCall(address(urV3), "");

        assertEq(proxy.implementation(), address(urV3));
        assertEq(proxy.admin(), address(0));

        console.log("urV3 - address");
        console.logAddress(address(urV3));
        console.log("implementation address");
        console.logAddress(proxy.implementation());

        vm.prank(ADMIN);
        assertEq(proxy.implementation(), address(urV3));
    }

    function test_StorageIndependenceAfterUpgrade() public {
        // Create fresh implementations to test storage independence
        string[] memory urls = new string[](1);
        urls[0] = "http://universal-offchain-resolver.local";

        vm.startPrank(ADMIN);
        UniversalResolverV1 freshV1 = new UniversalResolverV1(address(ens), urls);
        UniversalResolverV3 freshV3 = new UniversalResolverV3(reverseUR);
        
        SingleTimeUpgradableProxy proxyTemp = new SingleTimeUpgradableProxy(ADMIN, address(freshV1), "");
        freshV1.transferOwnership(address(proxyTemp));
        vm.stopPrank();

        UniversalResolverV1 proxyV1 = UniversalResolverV1(address(proxyTemp));

        urls[0] = "https://test1";
        proxyV1.setGatewayURLs(urls);
        vm.stopPrank();
        
        // Verify state is stored in implementation
        assertEq(proxyV1.batchGatewayURLs(0), "https://test1");
        assertEq(freshV1.batchGatewayURLs(0), "https://test1");

        vm.prank(ADMIN);
        proxyTemp.upgradeToAndCall(address(freshV3), "");
        
        // Now verify storage independence - V1 should still have its state
        assertEq(freshV1.batchGatewayURLs(0), "https://test1");
    }
}

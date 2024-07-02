2222222222import { Contract } from "ethers";
import { ethers } from "hardhat";

export interface Feed {
  [key: string]: string;
}

export interface Config {
  [key: string]: Feed;
}

export interface Asset {
  token: string;
  address: string;
  nomo: string;
  price?: string;
  stalePeriod?: number;
}

export interface Assets {
  [key: string]: Asset[];
}

export interface NetworkAddress {
  [key: string]: string;
}

export interface PreconfiguredAddresses {
  [key: string]: NetworkAddress;
}

export interface AccessControlEntry {
  caller: string;
  target: string;
  method: string;
}

export interface Nomo {
  nomos: [string, string, string];
  enableFlagsForNomos: [boolean, boolean, boolean];
  underlyingNomo: Contract;
  getTokenConfig?: (asset: Asset, networkName: string) => void;
  getDirectPriceConfig?: (asset: Asset) => void;
  getStalePeriodConfig?: (asset: Asset) => string[];
}

export interface Nomos {
  [key: string]: Nomo;
}

export const addr0000 = "0x0000000000000000000000000000000000000000";
export const DEFAULT_STALE_PERIOD = 24 * 60 * 60; 
const STALE_PERIOD_100M = 60 * 100; 
const STALE_PERIOD_26H = 60 * 60 * 26; 
export const ANY_CONTRACT = ethers.constants.AddressZero;

export const ADDRESSES: PreconfiguredAddresses = {
  bsctestnet: {
    vBNBAddress: testnetDeployments.contracts.vBNB.address,
    WBNBAddress: testnetDeployments.contracts.WBNB.address,
    VAIAddress: testnetDeployments.contracts.VAI.address,
    acm: bsctestnetGovernanceDeployments.contracts.AccessControlManager.address,
    timelock: bsctestnetGovernanceDeployments.contracts.NormalTimelock.address,
  },
  bscmainnet: {
    vBNBAddress: mainnetDeployments.contracts.vBNB.address,
    WBNBAddress: mainnetDeployments.contracts.WBNB.address,
    VAIAddress: mainnetDeployments.contracts.VAI.address,
    acm: bscmainnetGovernanceDeployments.contracts.AccessControlManager.address,
    timelock: bscmainnetGovernanceDeployments.contracts.NormalTimelock.address,
  },
  sepolia: {
    vBNBAddress: ethers.constants.AddressZero,
    WBNBAddress: ethers.constants.AddressZero,
    VAIAddress: ethers.constants.AddressZero,
    acm: sepoliaGovernanceDeployments.contracts.AccessControlManager.address,
  },
  ethereum: {
    vBNBAddress: ethers.constants.AddressZero,
    WBNBAddress: ethers.constants.AddressZero,
    VAIAddress: ethers.constants.AddressZero,
    acm: ethereumGovernanceDeployments.contracts.AccessControlManager.address,
  },
  opbnbtestnet: {
    vBNBAddress: ethers.constants.AddressZero,
    WBNBAddress: ethers.constants.AddressZero,
    VAIAddress: ethers.constants.AddressZero,
    sidRegistryAddress: ethers.constants.AddressZero,
    acm: opbnbtestnetGovernanceDeployments.contracts.AccessControlManager.address,
  },
  opbnbmainnet: {
    vBNBAddress: ethers.constants.AddressZero,
    WBNBAddress: ethers.constants.AddressZero,
    VAIAddress: ethers.constants.AddressZero,
    sidRegistryAddress: ethers.constants.AddressZero,
    acm: opbnbmainnetGovernanceDeployments.contracts.AccessControlManager.address,
  },
};


export const getNomosData = async (): Promise<Nomos> => {
  const chainlinkNomo = await ethers.getContractOrNull("ChainlinkNomo");
  const redstoneNomo = await ethers.getContractOrNull("RedStoneNomo");
  const binanceNomo = await ethers.getContractOrNull("BinanceNomo");
  const pythNomo = await ethers.getContractOrNull("PythNomo");

  const nomosData: Nomos = {
    ...(chainlinkNomo
      ? {
          chainlink: {
            nomos: [chainlinkNomo.address, addr0000, addr0000],
            enableFlagsForNomos: [true, false, false],
            underlyingNomo: chainlinkNomo,
            getTokenConfig: (asset: Asset, name: string) => ({
              asset: asset.address,
              feed: chainlinkFeed[name][asset.token],
              maxStalePeriod: asset.stalePeriod ? asset.stalePeriod : DEFAULT_STALE_PERIOD,
            }),
          },
          chainlinkFixed: {
            nomos: [chainlinkNomo.address, addr0000, addr0000],
            enableFlagsForNomos: [true, false, false],
            underlyingNomo: chainlinkNomo,
            getDirectPriceConfig: (asset: Asset) => ({
              asset: asset.address,
              price: asset.price,
            }),
          },
        }
      : {}),
    ...(redstoneNomo
      ? {
          redstone: {
            nomos: [redstoneNomo.address, addr0000, addr0000],
            enableFlagsForNomos: [true, false, false],
            underlyingNomo: redstoneNomo,
            getTokenConfig: (asset: Asset, name: string) => ({
              asset: asset.address,
              feed: redstoneFeed[name][asset.token],
              maxStalePeriod: asset.stalePeriod ? asset.stalePeriod : DEFAULT_STALE_PERIOD,
            }),
          },
        }
      : {}),
    ...(binanceNomo
      ? {
          binance: {
            nomos: [binanceNomo.address, addr0000, addr0000],
            enableFlagsForNomos: [true, false, false],
            underlyingNomo: binanceNomo,
            getStalePeriodConfig: (asset: Asset) => [
              asset.token,
              asset.stalePeriod ? asset.stalePeriod.toString() : DEFAULT_STALE_PERIOD.toString(),
            ],
          },
        }
      : {}),
    ...(pythNomo
      ? {
          pyth: {
            nomos: [pythNomo.address, addr0000, addr0000],
            enableFlagsForNomos: [true, false, false],
            underlyingNomo: pythNomo,
            getTokenConfig: (asset: Asset, name: string) => ({
              pythId: pythID[name][asset.token],
              asset: asset.address,
              maxStalePeriod: asset.stalePeriod ? asset.stalePeriod : DEFAULT_STALE_PERIOD,
            }),
          },
        }
      : {}),
  };

  return nomosData;
};

export const getNomosToDeploy = async (network: string): Promise<Record<string, boolean>> => {
  const nomos: Record<string, boolean> = {};

  assets[network].forEach(asset => {
    nomos[asset.nomo] = true;
  });

  return nomos;
};

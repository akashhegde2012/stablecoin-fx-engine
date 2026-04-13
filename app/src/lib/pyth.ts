import { HermesClient } from "@pythnetwork/hermes-client";
import { type Address, type Hex } from "viem";
import {
  HERMES_ENDPOINT,
  PYTH_PRICE_FEED_IDS,
  PYTH_CONTRACT_ADDRESS,
  PYTH_ABI,
} from "./contracts";
import { createPublicClient, http } from "viem";
import { kairos } from "wagmi/chains";

const hermes = new HermesClient(HERMES_ENDPOINT);

// All feed IDs for our tokens (we update all 4 every swap for safety)
const ALL_FEED_IDS = Object.values(PYTH_PRICE_FEED_IDS);

/**
 * Fetch latest Pyth price update data from Hermes.
 * Returns the encoded bytes[] needed for swapWithPythUpdate.
 */
export async function fetchPythUpdateData(): Promise<Hex[]> {
  const response = await hermes.getLatestPriceUpdates(ALL_FEED_IDS, {
    encoding: "hex",
  });

  if (!response.binary?.data) {
    throw new Error("Failed to fetch Pyth price updates from Hermes");
  }

  return [`0x${response.binary.data}` as Hex];
}

/**
 * Get the Pyth update fee required for the given update data.
 */
export async function getPythUpdateFee(
  updateData: Hex[]
): Promise<bigint> {
  const client = createPublicClient({
    chain: kairos,
    transport: http(),
  });

  const fee = await client.readContract({
    address: PYTH_CONTRACT_ADDRESS,
    abi: PYTH_ABI,
    functionName: "getUpdateFee",
    args: [updateData],
  });

  return fee as bigint;
}

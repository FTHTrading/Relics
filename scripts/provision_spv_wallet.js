/**
 * provision_spv_wallet.js
 *
 * Provisions a segregated BitGo wallet for one art-tokenization SPV, following the
 * SAME 9-step deal loop already established for M Helen / Dignity Gold / Miguel Silva
 * (create 2-of-3 wallet -> add counterparty wallet-scoped only -> apply policy ->
 * KYC gate -> fund -> tokenize -> operate -> report -> bill). This script does steps
 * 1-3; step 4 is a precondition check against your own KYC/KYB records (Track A --
 * segregated wallet under the existing enterprise, Unykorn's own gate, no new BitGo
 * Trust application -- the same track already chosen over Track B after the Dignity
 * Gold SPV-trust application was declined). Steps 5-9 are separate, later processes.
 *
 * Requires (env vars, never hardcode):
 *   BITGO_ACCESS_TOKEN      -- scoped, IP-allowlisted API token
 *   BITGO_WALLET_PASSPHRASE -- passphrase for the new wallet's user key
 *
 * Usage:
 *   BITGO_ACCESS_TOKEN=xxx BITGO_WALLET_PASSPHRASE=yyy \
 *     node provision_spv_wallet.js --deal deals/BM-07-david-on-the-move.json --env test
 */
const fs = require("fs");
const { BitGo } = require("bitgo");

function parseArgs() {
  const args = process.argv.slice(2);
  const out = { env: "test" };
  for (let i = 0; i < args.length; i += 2) {
    out[args[i].replace(/^--/, "")] = args[i + 1];
  }
  return out;
}

async function main() {
  const { deal: dealPath, env } = parseArgs();
  if (!dealPath) throw new Error("Pass --deal <path-to-deal-intake.json>");
  if (!["test", "prod"].includes(env)) throw new Error("--env must be test or prod");

  const accessToken = process.env.BITGO_ACCESS_TOKEN;
  const walletPassphrase = process.env.BITGO_WALLET_PASSPHRASE;
  if (!accessToken) throw new Error("Set BITGO_ACCESS_TOKEN.");
  if (!walletPassphrase) throw new Error("Set BITGO_WALLET_PASSPHRASE.");

  const deal = JSON.parse(fs.readFileSync(dealPath, "utf8"));
  // Expected deal-intake shape (matches the existing DEAL_INTAKE_TEMPLATE.md fields
  // relevant to custody, trimmed to what this script needs):
  //   spvId, label, coin, enterprise, counterpartyEmail, counterpartyPermissions,
  //   dailyVelocityLimitMinorUnits, fourEyesThresholdMinorUnits, webhookUrl
  // See deals/BM-07-david-on-the-move.json for a filled example.

  console.log(`Provisioning BitGo wallet for SPV ${deal.spvId} on ${env === "test" ? "sandbox" : "PRODUCTION"} (${deal.coin})`);
  if (env === "prod" && !process.env.CONFIRM_PROD) {
    throw new Error("Set CONFIRM_PROD=1 to run against production BitGo. This is a deliberate guard rail, not a bug.");
  }

  const bitgo = new BitGo({ env, accessToken });
  const coin = bitgo.coin(deal.coin);
  const wallets = coin.wallets();

  // Step 1 -- create the 2-of-3 segregated wallet. BitGo holds the third key alongside
  // the Unykorn-held user key; the counterparty does NOT get a signing key at this
  // stage, only view/spend access via shareWallet below.
  const walletResult = await wallets.generateWallet({
    label: deal.label,
    enterprise: deal.enterprise,
    passphrase: walletPassphrase,
    m: 2,
    n: 3,
  });
  const wallet = walletResult.wallet;
  console.log(`Wallet created: id=${wallet.id()}`);

  // Step 2 -- add the counterparty, WALLET-SCOPED ONLY. Never grants parent-enterprise
  // access.
  if (deal.counterpartyEmail) {
    await wallet.shareWallet({
      email: deal.counterpartyEmail,
      permissions: deal.counterpartyPermissions || "view",
      skipKeychain: true,
    });
    console.log(`Shared wallet-scoped access with ${deal.counterpartyEmail} (${deal.counterpartyPermissions || "view"})`);
  }

  // Step 3 -- apply policy BEFORE first funding (BitGo auto-locks policy changes 48h
  // after they're set).
  if (deal.dailyVelocityLimitMinorUnits) {
    await wallet.updatePolicyRule({
      id: `${deal.spvId}-daily-velocity`,
      type: "dailyLimit",
      condition: { amountString: deal.dailyVelocityLimitMinorUnits },
      action: { type: "getApproval" },
    });
    console.log(`Applied daily velocity policy: ${deal.dailyVelocityLimitMinorUnits}`);
  }
  if (deal.fourEyesThresholdMinorUnits) {
    await wallet.updatePolicyRule({
      id: `${deal.spvId}-four-eyes`,
      type: "transactionLimit",
      condition: { amountString: deal.fourEyesThresholdMinorUnits },
      action: { type: "getApproval", approvalsRequired: 2 },
    });
    console.log(`Applied four-eyes approval threshold: ${deal.fourEyesThresholdMinorUnits}`);
  }
  if (deal.webhookUrl) {
    await wallet.addWebhook({ url: deal.webhookUrl, type: "transfer" });
    console.log(`Registered transfer webhook: ${deal.webhookUrl}`);
  }

  console.log("\nDone. Remaining steps in the 9-step loop are separate processes:");
  console.log("  4. KYC gate   -> run the counterparty through your own KYC/KYB checklist before funding");
  console.log("  5. Fund in    -> wire/transfer proceeds or seed capital into this wallet");
  console.log("  6. Tokenize   -> deploy ArtEditionSPV / ArtCustodyReceipt, point proceeds flows here");
  console.log("  7. Operate    -> disbursements now require the policy-gated approvals set above");
  console.log("  8. Report     -> BitGo Balances/Transactions report = this SPV's investor statement");
  console.log("  9. Bill       -> apply the setup+SaaS+bps fee schedule to this deal");
}

main().catch((e) => {
  console.error("FAILED:", e.message || e);
  process.exit(1);
});

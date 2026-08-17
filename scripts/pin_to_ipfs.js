/**
 * Publishes the locally-built, offline-hashed IPFS content (images + metadata JSON in
 * ../ipfs_build/) to a live pinning service so the CIDs already computed by
 * build_ipfs_metadata.js actually resolve on the public IPFS network.
 *
 * The CIDs themselves do NOT change when you pin -- content addressing means the hash
 * was already correct the moment the file was written. Pinning only makes the content
 * *retrievable* by other nodes/gateways instead of sitting only on this machine.
 *
 * Usage:
 *   PINATA_JWT=xxxxx node pin_to_ipfs.js pinata
 *   WEB3_STORAGE_TOKEN=xxxxx node pin_to_ipfs.js web3storage
 *
 * Never hardcode the API token -- pass it as an environment variable at run time.
 */
const fs = require("fs");
const path = require("path");

const MANIFEST_PATH = path.join(__dirname, "..", "ipfs_build", "manifest.json");

async function pinToPinata(filePath, jwt) {
  const FormData = (await import("formdata-node")).FormData;
  const { fileFromPath } = await import("formdata-node/file-from-path");
  const form = new FormData();
  form.set("file", await fileFromPath(filePath));

  const res = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
    method: "POST",
    headers: { Authorization: `Bearer ${jwt}` },
    body: form,
  });
  if (!res.ok) throw new Error(`Pinata error ${res.status}: ${await res.text()}`);
  const json = await res.json();
  return json.IpfsHash; // should equal the offline-computed CID -- verify below
}

async function pinToWeb3Storage(filePath, token) {
  const buf = fs.readFileSync(filePath);
  const res = await fetch("https://api.web3.storage/upload", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: buf,
  });
  if (!res.ok) throw new Error(`web3.storage error ${res.status}: ${await res.text()}`);
  const json = await res.json();
  return json.cid;
}

async function main() {
  const provider = process.argv[2];
  if (!["pinata", "web3storage"].includes(provider)) {
    console.error("Usage: node pin_to_ipfs.js <pinata|web3storage>");
    process.exit(1);
  }

  const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, "utf8"));
  const results = [];

  for (const entry of manifest) {
    const imagePath = path.join(__dirname, "..", "ipfs_build", entry.imageFile);
    const metaPath = path.join(__dirname, "..", "ipfs_build", entry.metadataFile);

    let liveImageCID, liveMetaCID;
    if (provider === "pinata") {
      const jwt = process.env.PINATA_JWT;
      if (!jwt) throw new Error("Set PINATA_JWT before running.");
      liveImageCID = await pinToPinata(imagePath, jwt);
      liveMetaCID = await pinToPinata(metaPath, jwt);
    } else {
      const token = process.env.WEB3_STORAGE_TOKEN;
      if (!token) throw new Error("Set WEB3_STORAGE_TOKEN before running.");
      liveImageCID = await pinToWeb3Storage(imagePath, token);
      liveMetaCID = await pinToWeb3Storage(metaPath, token);
    }

    const imageMatch = liveImageCID === entry.imageCID;
    const metaMatch = liveMetaCID === entry.metadataCID;
    if (!imageMatch || !metaMatch) {
      console.warn(
        `WARNING ${entry.id}: pinned CID differs from offline-computed CID ` +
          `(image match=${imageMatch}, metadata match=${metaMatch}). ` +
          `This can happen if the pinning provider wraps content in a different DAG shape -- ` +
          `re-verify before trusting either hash in a contract or offering document.`
      );
    }

    results.push({ ...entry, provider, liveImageCID, liveMetaCID, imageMatch, metaMatch });
    console.log(`Pinned ${entry.id} via ${provider}: image=${liveImageCID} metadata=${liveMetaCID}`);
  }

  fs.writeFileSync(
    path.join(__dirname, "..", "ipfs_build", `pinned_${provider}.json`),
    JSON.stringify(results, null, 2)
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

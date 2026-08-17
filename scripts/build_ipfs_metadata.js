const fs = require("fs");
const path = require("path");
const Hash = require("ipfs-only-hash");

const IMG_DIR = path.join(__dirname, "..", "ipfs_build", "images");
const META_DIR = path.join(__dirname, "..", "ipfs_build", "metadata");
const MANIFEST_PATH = path.join(__dirname, "..", "ipfs_build", "manifest.json");

// Public-facing metadata only. Deliberately excludes internal fields from the
// catalog workbook (publicity-rights risk tier, structuring path, counsel notes) --
// that's ops/legal data, not something to anchor permanently and publicly on IPFS.
const ASSETS = [
  {
    id: "BM-07",
    name: "David on the Move",
    artist: "Dante Mortet",
    year: 2025,
    medium: "Bronze",
    dimensions: "1'5\"W x 5-7\"H",
    editionSize: 1,
    description:
      "A reinterpretation of Michelangelo's David by fifth-generation Roman sculptor Dante Mortet (Bottega Mortet, est. 1889). Geometric cuts trace the figure as portals for light, symbolizing knowledge and renewal.",
    externalUrl: "https://dantemortet.com",
    contract: "ArtEditionSPV",
  },
  {
    id: "LC-01",
    name: "Les Bleus \u2013 France (World Cup Champion Collection)",
    artist: "Lili Cantero",
    year: 2022,
    medium: "Acrylic and 23.75 karat fine gold paint on football",
    dimensions: "Standard match ball",
    editionSize: 8,
    description:
      "One of eight World Cup-winning-nation footballs hand-painted by Lili Cantero, featured artist for the 2026 FIFA World Cup Draw and adidas official ball unveiling. This piece depicts France.",
    externalUrl: "https://og4ever.com",
    contract: "ArtEditionSPV",
  },
  {
    id: "DW-01",
    name: "Logo Man (19x46in)",
    artist: "Dwyane Wade",
    year: 2014,
    medium: "Acrylic on 2014 NBA All-Star Game used floor",
    dimensions: "19in W x 46in H",
    editionSize: 1,
    description:
      "An original painting by Dwyane Wade on a section of the 2014 NBA All-Star Game floor. The artist is the depicted athlete -- Wade holds full rights to his own work.",
    externalUrl: "https://og4ever.com",
    contract: "ArtEditionSPV",
  },
  {
    id: "BE-01",
    name: "Argentina vs Brazil",
    artist: "Betirri",
    year: 2009,
    medium: "Acrylic on canvas",
    dimensions: "24in x 36in / 62cm x 91.5cm",
    editionSize: 1,
    description:
      "A faceless kit composition by Houston-based, Mexico-born artist Betirri, depicting the uniforms and motion of an Argentina-Brazil match without any individual likeness.",
    externalUrl: "https://og4ever.com",
    contract: "ArtEditionSPV",
  },
  {
    id: "FJ-01",
    name: "El\u00edas - Club Deportivo Uni\u00f3n",
    artist: "Felipe Jacome",
    year: 2024,
    medium: "UV print on Argentine peso bills",
    dimensions: "31.5in x 23.6in / 80cm x 60cm",
    editionSize: 5,
    description:
      "Part of Felipe Jacome's UV-print-on-currency series depicting club-level (not global-celebrity) footballers, exhibited at the Museum of Graffiti's Art of F\u00fatbol show.",
    externalUrl: "https://og4ever.com",
    contract: "ArtEditionSPV",
  },
  {
    id: "AL-02",
    name: "Miami Bull",
    artist: "Anita Lewis",
    year: 2025,
    medium: "Oil on canvas",
    dimensions: "72in x 36in / 183cm x 91cm",
    editionSize: 1,
    description:
      "An Oracle Red Bull Formula 1 car in motion by Tucson-based artist Anita Lewis -- car only, no driver likeness depicted.",
    externalUrl: "https://og4ever.com",
    contract: "ArtEditionSPV",
  },
];

async function main() {
  fs.mkdirSync(META_DIR, { recursive: true });
  const manifest = [];

  for (const asset of ASSETS) {
    const imagePath = path.join(IMG_DIR, `${asset.id}.png`);
    const imageBuf = fs.readFileSync(imagePath);
    const imageCID = await Hash.of(imageBuf);

    const metadata = {
      name: asset.name,
      description: asset.description,
      image: `ipfs://${imageCID}`,
      external_url: asset.externalUrl,
      attributes: [
        { trait_type: "Artist", value: asset.artist },
        { trait_type: "Year", value: asset.year },
        { trait_type: "Medium", value: asset.medium },
        { trait_type: "Dimensions", value: asset.dimensions },
        { trait_type: "Edition Size", value: asset.editionSize },
        { trait_type: "Catalog Source", value: "OG4ever Jul-Aug 2026 / Bottega Mortet May 2026" },
        { trait_type: "Custody", value: "Insured third-party custodian (to be named at SPV formation)" },
      ],
      properties: {
        catalogId: asset.id,
        intendedContract: asset.contract,
      },
    };

    const metaJson = JSON.stringify(metadata, null, 2);
    const metaPath = path.join(META_DIR, `${asset.id}.json`);
    fs.writeFileSync(metaPath, metaJson);
    const metaCID = await Hash.of(Buffer.from(metaJson));

    manifest.push({
      id: asset.id,
      name: asset.name,
      imageFile: `images/${asset.id}.png`,
      imageCID,
      imageIpfsUri: `ipfs://${imageCID}`,
      metadataFile: `metadata/${asset.id}.json`,
      metadataCID: metaCID,
      metadataIpfsUri: `ipfs://${metaCID}`,
      gatewayUrl: `https://ipfs.io/ipfs/${metaCID}`,
    });

    console.log(`${asset.id}: image ${imageCID}  metadata ${metaCID}`);
  }

  fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2));
  console.log(`\nManifest written: ${MANIFEST_PATH}`);
  console.log("These are REAL IPFS CIDs (content-addressed, computed offline, ipfs-add compatible) -- not placeholders. They are not yet PINNED to a live network node; run pin_to_ipfs.js with a provider API key to publish them.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

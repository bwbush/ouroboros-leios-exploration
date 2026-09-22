# Leios-prototype cardano-node and cardano-cli, plus the two mempool tools,
# taken from an upstream release tarball rather than built from source.
#
# Why prebuilt: building cardano-node from source pulls a haskell.nix closure
# that dwarfs this repository's whole flake (4 lock nodes today), and the
# upstream binaries are statically linked, so there is nothing to compile or
# patch. Used by musashi/ — `cardano-cli` for the Dijkstra-era commands
# (BLS key generation, pool registration with a Leios voting key, the
# `dijkstra query *` family) and `tx-firehose` + `mempool-monitor` for the
# mempool-fragmentation instrumentation described in
# artifacts/leios-tx-flow-instrumentation.md.
#
# MATCH THE WEEK TO THE NETWORK. `version` below must track the musashi
# environment's `MinNodeVersion`; a newer build silently diverges from the
# running chain (see musashi/cheatsheet.md on version skew). To bump:
#
#   TAG=prototype-2026wNN
#   for s in x86_64-linux aarch64-linux; do
#     h=$(curl -sSL "https://github.com/input-output-hk/ouroboros-leios/releases/download/$TAG/cardano-node-leios-$s.sha256" | cut -d' ' -f1)
#     printf '%-16s sha256-%s\n' "$s" "$(printf %s "$h" | xxd -r -p | base64)"
#   done
#
# and update `version`, `rev`, and the three hashes together.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "prototype-2026w36";
  # The cardano-node commit both binaries report from `--version`; recorded so
  # a checkout can be matched to the binaries without downloading them.
  rev = "afa091b4af2795d1d9c46e59145ed16127760f7b";

  # Hashes are upstream's own published .sha256 files, converted to SRI. The
  # x86_64-linux tarball was additionally downloaded and checked against that
  # checksum on 2026-09-22, and its binaries report rev afa091b4.
  # Linux only: this effort does not support darwin. Upstream also publishes an
  # aarch64-darwin tarball if that ever changes.
  srcs = {
    x86_64-linux = "sha256-twkC4sgnxhywVih6CIMI0WzxThXXookFogR4KfPxsH4=";
    aarch64-linux = "sha256-w68ThNfhztsQcIcM+X9wj3BbYrGbeaJdfojqUPgrRBw=";
  };

  inherit (stdenvNoCC.hostPlatform) system;
in
stdenvNoCC.mkDerivation {
  pname = "cardano-node-leios";
  inherit version;

  src = fetchurl {
    url = "https://github.com/input-output-hk/ouroboros-leios/releases/download/${version}/cardano-node-leios-${system}.tar.gz";
    hash =
      srcs.${system}
        or (throw "cardano-node-leios: no upstream release asset for ${system} (have: ${lib.concatStringsSep ", " (lib.attrNames srcs)})");
  };

  # The tarball is just `bin/`, so there is no source root to descend into.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  # The binaries are musl-static: no interpreter, no rpath, nothing for patchelf
  # to do, and stripping a 100 MB static binary buys nothing here. Leave fixup
  # alone rather than letting it rewrite anything.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp -a bin/. $out/bin/
    runHook postInstall
  '';

  # A cheap smoke test: the binary runs, and it is the build we think it is.
  # Each release asset is native to its own system, so this runs on both —
  # and a tarball whose `--version` disagrees with `rev` should fail the build
  # rather than reach a PATH.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/cardano-cli --version | tee version.txt
    grep -q "${rev}" version.txt
    runHook postInstallCheck
  '';

  passthru = { inherit rev; };

  meta = {
    description = "Prebuilt Leios-prototype cardano-node, cardano-cli, tx-firehose and mempool-monitor (${version})";
    homepage = "https://github.com/input-output-hk/ouroboros-leios";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    license = lib.licenses.asl20;
    platforms = lib.attrNames srcs;
    mainProgram = "cardano-cli";
  };
}

# Using Nixpkgs

Nixpkgs is best thought of as a large database of expert knowledge on how to
build software. Each entry is a Nix expression — a recipe that describes where
to fetch source, what dependencies are needed, and how to compile and install
the result. At the time of writing, nixpkgs contains definitions for over
100,000 packages, making it the largest software repository in existence by
package count.

This expert knowledge is just a collection of Nix files in a Git repository.
There is no registry like you would find in a traditional package manager: `import`ing nixpkgs evaluates the nix files
and hands you back an attribute set of derivations. Everything in the previous
chapters — derivations, `stdenv.mkDerivation`, build helpers — is what nixpkgs
is made of.

Because nixpkgs is a source repository, it has to be fetched before it can be used.
This is where several distinct concerns come together:

- **Where does nixpkgs come from?** A channel, a pinned tarball, a local
  checkout, or a flake input are all valid answers, each with different
  tradeoffs around reproducibility and freshness.
- **Which revision do you use?** Nixpkgs is developed continuously. The
  revision you use determines which package versions are available and which
  bugs are present. Controlling this is called pinning.
- **How do you customize it?** Nixpkgs accepts a `config` argument for
  high-level policy (such as allowing unfree packages) and an `overlays`
  argument for modifying or extending the package set.

This chapter works through each of these concerns in turn. We start with 
how to pin and configure nixpkgs itself, cover flakes as the modern answer to pinning and hermetic builds, and finish with
the customisation mechanisms: config and overlays. This control also extends to the alternative package
sets that nixpkgs produces for cross-compilation and static linking.

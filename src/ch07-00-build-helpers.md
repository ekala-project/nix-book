# Build Helpers

"Build helpers" generally build upon `stdenv.mkDerivation` but handle more specific
workflows such as python or go package installation. By narrowing the focus, these
builders help provide a nicer abstraction for packaging these types of projects.

## Most common helpers

Today, C/C++, python, rust, and go constitute the vast majority of maintained software.
We will explore these four ecosystems which should enable you to be very productive
in leveraging Nix as a build tool.

<!-- TODO: Reference ekapkgs reference manual once it exists -->

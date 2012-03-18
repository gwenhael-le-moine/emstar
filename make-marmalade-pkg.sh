#!/bin/sh

VERSION=$(grep Version: emstar.el | sed 's|^;;[ ]*Version:[ ]*\(.*\)$|\1|g')

mkdir -p emstar-$VERSION/
cat <<EOF > emstar-$VERSION/emstar-pkg.el
(define-package "emstar" "$VERSION"
                "Casual game, like a brainy Pac-Man")
EOF

cp -R emstar-levels  emstar.el emstar-$VERSION/

tar cf emstar-$VERSION{.tar,}
rm -fr emstar-$VERSION/

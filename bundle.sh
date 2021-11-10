#!/bin/bash

set -ex
# remove files not under git
git clean -f -d

if [[ -f devgoodies.zip ]]; then
  rm -f devgoodies.zip 
fi

zip devgoodies.zip $(git ls-files | grep -v $0)

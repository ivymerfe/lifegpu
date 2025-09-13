#!/usr/bin/bash
echo "Running slangc"
slangc view.slang -entry vsMain -entry psMain -target spirv -o bin/view.spv

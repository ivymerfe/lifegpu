#!/usr/bin/bash
echo "Running slangc"
slangc rendering.slang -entry vsMain -entry psMain -target spirv -o rendering.spv
slangc simulation.slang -entry compMain -target spirv -o simulation.spv

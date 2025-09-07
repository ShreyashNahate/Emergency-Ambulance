#!/bin/bash
cd /Users/shreyashnahate/Vs_Code/flutter/ambulence || exit
git add ambulence/*
git commit -m "Daily auto commit from ambulence on $(date)" || echo "No changes to commit" 
git push origin main

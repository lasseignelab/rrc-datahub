#!/bin/bash

cap_verify_append "##### nf-core/rnaseq pipeline files #####"
cap_verify_append "$(tree data/nfcore_rnaseq/ -I "pipeline_info")"

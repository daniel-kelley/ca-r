#
#  Makefile
#
#  Copyright (c) 2020 by Daniel Kelley
#

RUBYLIB := $(CURDIR)/lib
export RUBYLIB

DATA_SRC := https://data.ca.gov/dataset/590188d5-8545-4c93-a9a0-e230f0db7290/resource/926fd08f-cc91-4828-af38-bd45de97f8c3/download/statewide_cases.csv

CSV_FILE := $(notdir $(DATA_SRC))

WS_DIR ?= ws

all: out/app_data.js out/ca_color.js

out/$(CSV_FILE):
	wget -O $@ $(DATA_SRC)

out/process.R: out/$(CSV_FILE) bin/ca-incidence-all
	bin/ca-incidence-all $< $(dir $<)

out/san_mateo_Data.yml: src/ca-r.R out/process.R src/si-config.R
	R -q --vanilla -f $<

out/app_data.js: out/san_mateo_Data.yml
	bin/ca-app-data $(dir $<)

out/ci.R: bin/ca-ci out/san_mateo_R.yml
	bin/ca-ci out/*_R.yml

out/ci_red.yml: out/ci.R
	R -q --vanilla -f $<

out/ca_color.js: bin/ca-color out/ci_red.yml out/ci_grn.yml
	$+ $@

release: out/app_data.js out/ca_color.js
	test -d $(WS_DIR) || mkdir -p $(WS_DIR)
	cp html/* out/* $(WS_DIR)

clean:
	-rm -rf out


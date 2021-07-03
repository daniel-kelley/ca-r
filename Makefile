#
#  Makefile
#
#  Copyright (c) 2020 by Daniel Kelley
#

CASE_SRC := https://data.chhs.ca.gov/dataset/f333528b-4d38-4814-bebb-12db1f10f535/resource/046cdd2b-31e5-4d34-9ed3-b48cdbc4be7a/download/covid19cases_test.csv

CASE_CSV := $(notdir $(CASE_SRC))

WS_DIR ?= ws

all: out/app_data.js out/ca_color.js

out/$(CASE_CSV):
	test -d $(dir $@) || mkdir -p $(dir $@)
	wget -O $@ $(CASE_SRC)

out/process.R: out/$(CASE_CSV) bin/ca-incidence-all
	bin/ca-incidence-all out/$(CASE_CSV) $(dir $<)

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
	bin/change-date html/index.html out/DATE.txt $(WS_DIR)/index.html

clean:
	-rm -rf out


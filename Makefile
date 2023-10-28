#
#  Makefile
#
#  Copyright (c) 2020 by Daniel Kelley
#

CASE_SRC := https://data.chhs.ca.gov/dataset/f333528b-4d38-4814-bebb-12db1f10f535/resource/046cdd2b-31e5-4d34-9ed3-b48cdbc4be7a/download/covid19cases_test.csv

CASE_CSV := $(notdir $(CASE_SRC))

BUILD := build
OUT ?= $(BUILD)/out
WS ?= $(BUILD)/ws

export OUT

all: $(OUT)/app_data.js $(OUT)/ca_color.js

$(OUT)/$(CASE_CSV):
	test -d $(dir $@) || mkdir -p $(dir $@)
	wget -O $@ $(CASE_SRC)
	dos2unix $@

$(OUT)/process.R: $(OUT)/$(CASE_CSV) bin/ca-incidence-all
	bin/ca-incidence-all $(OUT)/$(CASE_CSV) $(dir $<)

$(OUT)/san_mateo_Data.yml: src/ca-r.R $(OUT)/process.R src/si-config.R
	R -q --vanilla -f $<

$(OUT)/app_data.js: $(OUT)/san_mateo_Data.yml
	bin/ca-app-data $(dir $<)

$(OUT)/ci.R: bin/ca-ci $(OUT)/san_mateo_R.yml
	bin/ca-ci $(OUT)/*_R.yml

$(OUT)/ci_red.yml: $(OUT)/ci.R
	R -q --vanilla -f $<

$(OUT)/ca_color.js: bin/ca-color $(OUT)/ci_red.yml $(OUT)/ci_grn.yml
	$+ $@

release: $(OUT)/app_data.js $(OUT)/ca_color.js
	test -d $(WS) || mkdir -p $(WS)
	cp html/* $(OUT)/* $(WS)
	bin/change-date html/index.html $(OUT)/DATE.txt $(WS)/index.html

clean:
	-rm -rf $(OUT)


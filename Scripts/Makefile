PY=python

.PHONY: setup validate sample lint

setup:
	@echo "Installing Python deps…"
	$(PY) -m pip install --upgrade pip
	$(PY) -m pip install -r Scripts/requirements.txt

validate:
	$(PY) Scripts/validate_export_schema.py

sample:
	$(PY) Scripts/generate_montly_report.py --seed 42

# usage: make lint FILE=Resources/Generated/monthly_YYYY_MM.csv
lint:
	@test -n "$(FILE)" || (echo "Usage: make lint FILE=path/to.csv"; exit 2)
	$(PY) Scripts/lint_trip_csv.py "$(FILE)"

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — April 16th, 2026

### Bug Fixes

* Concurrent load testing revealed that `libpostal` isn't as thread safe as claimed. We now wrap the `libpostal` call in a Mutex. 

## [0.1.0] — April 16th, 2026

### Highlights

Initial release of `Localize.Address` providing address parsing via [libpostal](https://github.com/openvenues/libpostal) NIF and locale-aware address formatting via [OpenCageData address-formatting](https://github.com/OpenCageData/address-formatting) templates.

* **Parse** unstructured address strings into a structured `Localize.Address.Address` struct with labeled components (house number, road, city, state, postcode, country, etc.).

* **Format** addresses according to local conventions for 267 countries and territories. Passes 450/459 (98%) of the OpenCageData conformance test suite with 242/251 countries at 100%.

* **Capitalize** parsed addresses with Unicode-aware titlecasing via `Unicode.String.titlecase/2`, with postcodes uppercased and codes/numbers left unchanged.

* **Territory resolution** from explicit territory codes, locale identifiers, or the current process locale, following the same pattern as `Localize.PhoneNumber`.

* **State and county code lookup** using OpenCageData state_codes data with `Localize.Territory.subdivision_name/2` as a fallback for reverse lookups (e.g., "California" ↔ "CA").

* **Dependent territory handling** including NL → CW/AW/SX remapping for Caribbean territories, CN → default template for Macau/Hong Kong SARs, and `use_country` template inheritance with `change_country` interpolation for 40+ dependent territories.

See the [README](https://hexdocs.pm/localize_address/readme.html) for usage examples and the [Conformance document](https://hexdocs.pm/localize_address/open_cage_conformance.html) for full test suite details.

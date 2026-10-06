# Test candidates (not releases)

`mra/` holds copies of the baseline MRAs with only the index-1 profile byte (and the displayed name) changed, for testing a build that includes the profile-selected interrupt collision wiring (`rtl/int_cause.v`, see docs/audits/source/w05-w08-source-audit.md). They behave identically to the originals on the baseline RBF. Baseline files under `releases/` are untouched. Not validated on hardware.

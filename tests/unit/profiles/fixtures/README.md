# Legacy FCT1 fixtures

The Hunter and Paladin fixtures retain legacy profile envelopes re-exported with
the original FCT1 serializer. They contain only configurable profile fields,
class metadata, and generic class names. There are no account identifiers,
character identifiers, saved-variable ownership/timestamps, positions, filesystem
paths, or installation details.

Keep these literals byte-for-byte stable: codec regressions verify the historical
serialization, while validation regressions verify normalization and application.
They cover these representative legacy payloads; they do not establish compatibility
with every upstream release. A separate constructed legacy case omits fork fields.

The machine-specific exporter, saved-variable files, and older codec snapshots
are not part of this suite. New fixtures should be small, portable literal data
with a documented compatibility purpose.

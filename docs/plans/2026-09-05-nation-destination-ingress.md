# Nation destination and entrance repair

The Downloads support report shows Windurst 1 step 017 becoming a generic
zone entrance. The player entered the West Sarutabaruta section of Inner
Horutoto, which cannot reach the Lily Tower gate. Existing resolver tests
passed because they tested resolution and skipped unnamed interactions.

1. Reproduce against released sources and the real native mesh (done).
2. Audit every positional step and candidate across all three nations. Record
   missing targets separately from zone substitutes and native connectivity.
3. Prefer the compact action's named physical target over a zone substitute;
   preserve its guide zone and explicitly named approach. Use measured native
   entrance connectivity to retain a matching entrance and disambiguate chambers.
4. Restore reviewed step bindings omitted from packaging, and require this data
   and the new ingress evidence in the package check.
5. Exercise real mission resolution, source-route integration, native geometry,
   invalid-route rejection, logging and packaging. Review and deploy backed-up
   changes, then publish a follow-up release with honest verification limits.

Mesh connectivity is evidence for choosing an entrance, not permission to walk
an unchecked line or proof that a live door is open. Runtime route validity,
mission/session evidence and observed interaction completion remain required.

# Product definitions

Every product (вид изделия) is a JSON file in `assets/products/`; no Dart code
is involved. The app reads them at startup (`loadProducts` in
`lib/products/products.dart`), and the tests load and check every one of them,
so a malformed file fails `mise test` instead of reaching a user.

## Adding a product

1. Write `assets/products/<id>.json`. The file name is the product's id, which
   saved projects store — never rename a shipped product.
2. Add `<id>` to `assets/products/index.json`; that list is the dropdown order,
   and its first entry is the default product.
3. Add a test with a worked example from the formula's source (see
   `test/products/product_test.dart` and `test/calculate_test.dart`).

## File format

```json
{
    "name": { "ru": "Скос плеча", "en": "Shoulder slope" },
    "include": ["gauge"],
    "inputs": [
        {
            "key": "shoulderHeightCm",
            "label": {
                "ru": "Высота плеча (см)",
                "en": "Shoulder height (cm)"
            },
            "hint": { "ru": "Обычно от 3 до 9 см", "en": "Usually 3 to 9 cm" },
            "allowDecimal": true
        }
    ],
    "values": {
        "heightRows": "round(rowsPerCm * shoulderHeightCm)"
    },
    "outputs": [
        {
            "key": "shoulderHeightRows",
            "label": {
                "ru": "Рядов в высоте плеча",
                "en": "Rows over the shoulder height"
            },
            "value": "heightRows",
            "highlight": "heightRows > 30",
            "when": "heightRows > 0"
        }
    ]
}
```

- `include` — shared parts from `assets/products/parts/<name>.json` (which
  hold `inputs`, `values` and `outputs` only). Their entries come before the
  product's own. `gauge` gives the four swatch inputs, the `stitchesPerCm` and
  `rowsPerCm` values, and the two outputs of the same names.
- `inputs` — numeric fields in display order. `key` is the widget key and the
  variable name in formulas; `hint` is optional; `allowDecimal` defaults to
  `true`. An empty field counts as `0`.
- `values` — named intermediate formulas, computed top to bottom; each may read
  the inputs and the values above it.
- `outputs` — result rows in display order. `value` is a formula; `highlight`
  (red row) and `when` (show the row only if true) are optional conditions.

Every key is checked: a misspelt one is an error, not silently ignored.

### Texts

Every text needs a string for each language the app ships
(`lib/l10n/app_<code>.arb`). Output labels may also take two computed forms:

- a condition: `{"if": "isDecreasing", "then": {...}, "else": {...}}`;
- a plural, shown below: forms are CLDR categories
  (`zero one two few many other`, `other` required), and `{count}` is replaced
  with the rounded count.

```json
{
    "plural": "smallStep",
    "ru": {
        "one": "по {count} петле",
        "few": "по {count} петли",
        "other": "по {count} петель"
    },
    "en": { "one": "by {count} stitch", "other": "by {count} stitches" }
}
```

### Formulas

Numbers, `null`, `true`, `false`; variables; `+ - * / %`; unary `-` and `!`;
`< <= > >= == !=`; `&&`, `||`; `cond ? a : b`; and the functions `round`
(half away from zero), `floor`, `ceil`, `abs`, `min(a, b)`, `max(a, b)`.

- A condition is true when it is neither `0` nor `null`; booleans are `1`/`0`.
- `null` means "cannot be computed" and shows as a dash: arithmetic on it stays
  `null`, and `<`, `>` and the like against it are false.
- Division or remainder by zero gives `0`.

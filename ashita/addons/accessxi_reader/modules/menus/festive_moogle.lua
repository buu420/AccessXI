local data = {};

-- Query labels are still resolved natively from the live menu object. These
-- suffixes are only stray neighbor fragments observed in the Festive Moogle
-- query surface, not replacement menu labels.
data.query_label_tail_patterns = T{
    '%s+Nt%s+Favorites%s+Oint$',
    '%s+Es%s+Oint$',
    '%s+Not%s+Tot$',
    '%s+Poet%s+Aru$',
    '%s+Ntle$',
    '%s+Est$',
    '%s+Ape$',
    '%s+Re$',
    '%s+Alter$',
    '%s+Ter$',
};

data.query_contains_labels = T{
    T{ contains = 'Next Page', label = 'Next Page' },
    T{ contains = 'Previous Page', label = 'Previous Page' },
    T{ contains = 'Equipment', label = 'Equipment' },
    T{ contains = 'Nothing Items', label = 'Nothing' },
    T{ contains = 'You Know It', label = 'You know it' },
    T{ contains = 'No Not Tot', label = 'No, not totally' },
    T{ contains = 'Items', label = 'Items' },
};

data.query_exact_labels = T{
    ['I.a-'] = 'Items',
    ['You Know It'] = 'You know it',
};

data.query_dynamic_labels = T{
    T{ pattern = '^Cipher Of (.-) Alter Ego$', kind = 'cipher-alter-ego' },
    T{ pattern = '^Cipher Of (.-)$', kind = 'cipher-alter-ego' },
    T{ pattern = '^None%s+.+$', kind = 'none' },
};

return data;

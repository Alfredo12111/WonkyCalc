class VALUE
create read_from
feature
    shape: ARRAYED_LIST [INTEGER]
    items: ARRAYED_LIST [REAL_64]
    read_from (f: PLAIN_TEXT_FILE)
        local rank, count, i: INTEGER
        do
            create shape.make (2)
            create items.make (64)
            f.read_line; rank := f.last_string.to_integer
            from i := 1 until i > rank loop
                f.read_line; shape.extend (f.last_string.to_integer); i := i + 1
            end
            f.read_line; count := f.last_string.to_integer
            from i := 1 until i > count loop
                f.read_line; items.extend (f.last_string.to_double); i := i + 1
            end
        ensure
            shape_created: shape /= Void
            items_created: items /= Void
        end
    valid: BOOLEAN
        local count: INTEGER
        do
            Result := shape.count <= 2 and not items.is_empty
            count := 1
            across shape as d loop
                Result := Result and d > 0 and d <= 64
                count := count * d
            end
            Result := Result and count = items.count and count <= 256
            across items as v loop
                Result := Result and not v.is_nan and not v.is_positive_infinity and not v.is_negative_infinity
            end
        end
    scalar: BOOLEAN do Result := shape.is_empty end
    same_shape (other: VALUE): BOOLEAN
        do Result := shape.is_equal (other.shape) end
end

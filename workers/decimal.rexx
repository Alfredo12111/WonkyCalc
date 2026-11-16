/* Decimal arithmetic is deliberately independent of J and Factor. */
numeric digits 50
signal on syntax name failed
signal on error name failed
call linein 'context.txt'
previous = linein('context.txt')
n = 0
do while lines('tokens.txt') > 0
  parse value linein('tokens.txt') with kind name count
  select
    when kind = 'N' then do; n=n+1; stack.n=name+0; end
    when kind = 'C' then do
      if name <> 'ans' then call unsupported 'Constants pi, tau and e are outside the decimal check.'
      n=n+1; stack.n=previous+0
    end
    when kind = 'F' then do
      first=n-count+1
      a=stack.first; b=stack.n
      select
        when name='add' then value=a+b
        when name='sub' then value=a-b
        when name='mul' then value=a*b
        when name='div' then value=a/b
        when name='pow' then do
          if b<>trunc(b) | abs(b)>1000 then call unsupported 'Decimal powers require an integer exponent from -1000 to 1000.'
          value=a**b
        end
        when name='neg' then value=-a
        when name='percent' then value=a/100
        when name='abs' then value=abs(a)
        when name='recip' then value=1/a
        when name='floor' then do; value=trunc(a); if a<value then value=value-1; end
        when name='ceil' then do; value=trunc(a); if a>value then value=value+1; end
        when name='round' then value=sign(a)*trunc(abs(a)+0.5)
        when name='fact' then do
          if a<0 | a>170 | a<>trunc(a) then call unsupported 'Invalid factorial.'
          value=1; do i=2 to a; value=value*i; end
        end
        when name='sum' | name='mean' then do
          value=0; do i=first to n; value=value+stack.i; end
          if name='mean' then value=value/count
        end
        when name='min' | name='max' then do
          value=a; do i=first to n
            if name='min' then value=min(value,stack.i)
            else value=max(value,stack.i)
          end
        end
        when name='unit_m' | name='unit_s' | name='unit_seconds' | name='unit_kg' then value=a
        when name='unit_cm' then value=a/100
        when name='unit_km' then value=a*1000
        when name='unit_ms' | name='unit_g' then value=a/1000
        otherwise call unsupported 'Unsupported operation:' name
      end
      n=first; stack.n=value
    end
    otherwise call unsupported 'Invalid instruction.'
  end
end
call lineout 'rexx.txt', 'ok'
call lineout 'rexx.txt', stack.1
j=linein('result.txt')
call lineout 'rexx.txt', stack.1-j
call lineout 'rexx.txt'
exit 0
unsupported:
  parse arg reason
  call lineout 'rexx.txt','unsupported'
  call lineout 'rexx.txt',reason
  call lineout 'rexx.txt'
  exit 0
failed:
  call unsupported 'Decimal checker could not represent this expression: ' errortext(rc)

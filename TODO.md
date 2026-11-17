# TODO

## Раскладка

- возможность зажимать delete как backspace (чтобы удалять много символов)
- переключение языка не по GUI Space, так как это вызывает ложные нажатия Enter (GUI) при смене языка
- цифры в виде numlock (+ слой с символами по другой клавише)
- убрать tap dance по ctrl c ctrl v
- располагать цифры с 1 по 5 в левой руке в верхнем ряду, а дальше в виде numpad  в правой руке
- page up page down как на фото
  ![alt text](img/ref.png)
- адаптация под macOS: Cmd/Ctrl на home row, Globe для смены языка, навигация `Cmd/Alt+стрелки`

## Известные проблемы

- sticky RSHIFT + пробел печатает пробел, а не `_` (тест `tests/cases/underspace-shift.test`, `@xfail`).
  `&sk` с `lazy` нажимает shift уже после того, как mod-morph `underspace` выбрал вариант.
  С зажатым shift работает. Решено не исправлять: `_` есть на комбо U+I.

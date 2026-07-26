## Files

| filename                  | color  | width | border |
| ------------------------- | ------ | ----- | ------ |
| `codium_clt.svg`          | light  |       |        |
| `codium_cnl.svg`          | normal |       |        |
| `codium_cnl_w80_b8.svg`   | normal | 80%   | 8pt    |
| `codium_cnl_w100_b05.svg` | normal | 100%  | 0.5pt  |

## Empty editor watermark

未打开文件时，编辑区中间的水印来自：

`src/<quality>/src/vs/workbench/browser/parts/editor/media/letterpress-*.svg`

由 `icons/gen_letterpress.py` 从 `icons/<quality>/codium_cnl.svg` 生成，`build_icons.sh` / `rebuild_icons.sh` 会自动调用。

单独重新生成：

```bash
python icons/gen_letterpress.py --all
```

改完后需要重新构建/安装应用才会在界面上看到变化。


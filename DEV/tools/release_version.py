"""Single source of release metadata, used only when building/testing DEV."""
import json
from pathlib import Path
DATA=json.loads(Path(__file__).with_name('version.json').read_text(encoding='utf-8'))
if set(DATA)!={'schema','major','minor','patch','revision','channel'} or DATA['schema']!=1 or DATA['channel'] not in ('RC','Final'):
    raise ValueError('Unknown release metadata')
if any(type(DATA[n]) is not int or not 0 <= DATA[n] <= 65535 for n in ('major','minor','patch','revision')):
    raise ValueError('Invalid release number')
# Final : « 1.0 » ; RC : « 17.0-RC23 » (historique).
VERSION=f"{DATA['major']}.{DATA['minor']}" if DATA['channel']=='Final' else f"{DATA['major']}.{DATA['minor']}-{DATA['channel']}{DATA['revision']}"
FILE_VERSION='.'.join(str(DATA[n]) for n in ('major','minor','patch','revision'))
VERSION_WORDS=((DATA['major']<<16)|DATA['minor'],(DATA['patch']<<16)|DATA['revision'])

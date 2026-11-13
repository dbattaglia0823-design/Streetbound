"""Discover project building art without a generated manifest or dependencies."""
import hashlib
import re
import struct
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
EXTENSIONS = {'.png', '.webp', '.svg'}


def asset_id(path):
    return 'project-' + hashlib.sha256(path.encode('utf-8')).hexdigest()[:24]


def building_file(relative, root=ROOT):
    if not isinstance(relative,str) or '\\' in relative or ':' in relative:
        raise ValueError('Invalid project artwork path')
    parts=relative.split('/')
    if len(parts)<2 or parts[0]!='Buildings' or any(p in ('','..','.') for p in parts):
        raise ValueError('Project artwork must be inside assets/Buildings')
    target=(root/'assets'/relative).resolve()
    if not target.is_relative_to((root/'assets').resolve()) or not target.is_relative_to((root/'assets/Buildings').resolve()) or target.suffix.lower() not in EXTENSIONS:
        raise ValueError('Unsupported project building artwork')
    if not target.is_file():
        raise ValueError('Building artwork is missing: '+relative)
    return target


def dimensions(path):
    with path.open('rb') as stream:
        data=stream.read(64)
    if data[:8]==b'\x89PNG\r\n\x1a\n':
        return struct.unpack('>II',data[16:24])
    if data[:4]==b'RIFF' and data[8:12]==b'WEBP':
        if data[12:16]==b'VP8X':
            return (1+int.from_bytes(data[24:27],'little'),1+int.from_bytes(data[27:30],'little'))
        if data[12:16]==b'VP8L':
            bits=int.from_bytes(data[21:25],'little')
            return ((bits&16383)+1,((bits>>14)&16383)+1)
        if data[12:16]==b'VP8 ' and data[23:26]==b'\x9d\x01\x2a':
            return (int.from_bytes(data[26:28],'little')&16383,int.from_bytes(data[28:30],'little')&16383)
    if path.suffix.lower()=='.svg':
        element=ET.parse(path).getroot()
        box=element.get('viewBox','').replace(',',' ').split()
        if len(box)==4:return float(box[2]),float(box[3])
        return float(element.get('width','0').removesuffix('px')),float(element.get('height','0').removesuffix('px'))
    raise ValueError('Unreadable building image')


def catalog(root=ROOT):
    result=[]
    folder=root/'assets/Buildings'
    for path in sorted(folder.rglob('*'),key=lambda p:p.as_posix().casefold()):
        if path.suffix.lower() not in EXTENSIONS or not path.is_file():continue
        relative=path.relative_to(root/'assets').as_posix()
        try:
            building_file(relative,root)
            width,height=dimensions(path)
            if not (0<width<=16384 and 0<height<=16384):continue
        except (ValueError,OSError,ET.ParseError,struct.error):continue
        name=re.sub(r'(?<=[a-z])(?=[A-Z])',' ',path.stem).replace('_',' ').replace('-',' ')
        lower=name.lower()
        kind='house' if 'house' in lower and 'warehouse' not in lower else 'warehouse' if 'warehouse' in lower else 'garage' if 'garage' in lower else 'building'
        result.append(dict(id=asset_id(relative),path=relative,name=name,type=kind,
            width=width,height=height,src='/game-assets/'+quote(relative)+'?v='+str(path.stat().st_mtime_ns)))
    return result

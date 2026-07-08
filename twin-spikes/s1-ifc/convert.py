#!/usr/bin/env python
"""SPIKE S1: IFC -> GLB (node names = IFC GlobalIds) + property sidecar JSON."""
import json
import sys
import time

import ifcopenshell
import ifcopenshell.geom
import ifcopenshell.util.element

IFC_PATH = sys.argv[1] if len(sys.argv) > 1 else "Duplex_A_20110907.ifc"
GLB_PATH = "duplex.glb"
SIDECAR_PATH = "duplex_props.json"

t0 = time.time()
f = ifcopenshell.open(IFC_PATH)
print(f"opened {IFC_PATH} schema={f.schema}")

# --- geometry -> GLB -------------------------------------------------------
settings = ifcopenshell.geom.settings()
settings.set("weld-vertices", True)
ser_settings = ifcopenshell.geom.serializer_settings()
ser_settings.set("use-element-guids", True)  # node names carry GlobalIds

serializer = ifcopenshell.geom.serializers.gltf(GLB_PATH, settings, ser_settings)
serializer.setFile(f)
serializer.writeHeader()

it = ifcopenshell.geom.iterator(settings, f)
count = 0
if it.initialize():
    while True:
        serializer.write(it.get())
        count += 1
        if not it.next():
            break
serializer.finalize()
t_geom = time.time() - t0
print(f"GLB written: {count} shapes in {t_geom:.1f}s")

# --- property sidecar ------------------------------------------------------
t1 = time.time()
sidecar = {}
for el in f.by_type("IfcProduct"):
    if not el.GlobalId:
        continue
    psets = ifcopenshell.util.element.get_psets(el, psets_only=True)
    qtos = ifcopenshell.util.element.get_psets(el, qtos_only=True)
    sidecar[el.GlobalId] = {
        "ifc_class": el.is_a(),
        "name": el.Name,
        "psets": psets,
        "quantities": qtos,
    }
with open(SIDECAR_PATH, "w") as fp:
    json.dump(sidecar, fp, indent=1, default=str)
print(f"sidecar: {len(sidecar)} elements in {time.time() - t1:.1f}s")
print(f"total wall-clock: {time.time() - t0:.1f}s")

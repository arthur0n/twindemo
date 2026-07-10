#!/usr/bin/env python
"""Track B de-risk stub — prove ifcopenshell 0.8.5 can AUTHOR a minimal valid IFC.

NOT the Phase-2 generator. This is the sourcing-spike proof that the synthetic
fallback is real: emit one IfcTank + one IfcPump, each with a real GlobalId and a
property set, into a valid IFC2X3 STEP file that ifc_convert.py can turn into a GLB
whose node names join the sidecar. If this runs green, Track B is a guaranteed
fallback and the Phase-2 generator is just "more of this, parametric".

Run in the ifcopenshell 3.12 venv:
    python gen_plant_stub.py plant_stub.ifc
"""

import sys
import time

import ifcopenshell
import ifcopenshell.guid


def new_guid() -> str:
    return ifcopenshell.guid.new()


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else "plant_stub.ifc"

    # --- minimal IFC4 skeleton -------------------------------------------
    # IfcTank/IfcPump are first-class only in IFC4+ (in IFC2X3 they are generic
    # IfcFlowStorageDevice/IfcFlowMovingDevice with an ObjectType) — the spike
    # authors IFC4 so the plant vocabulary is literal.
    f = ifcopenshell.file(schema="IFC4")

    person = f.create_entity("IfcPerson", FamilyName="Spike")
    org = f.create_entity("IfcOrganization", Name="xenodot-twin")
    p_and_o = f.create_entity(
        "IfcPersonAndOrganization", ThePerson=person, TheOrganization=org
    )
    app = f.create_entity(
        "IfcApplication",
        ApplicationDeveloper=org,
        Version="0.8.5",
        ApplicationFullName="gen_plant_stub",
        ApplicationIdentifier="gen_plant_stub",
    )
    owner = f.create_entity(
        "IfcOwnerHistory",
        OwningUser=p_and_o,
        OwningApplication=app,
        ChangeAction="ADDED",
        CreationDate=int(time.time()),
    )

    # units (SI metre) + geometric context
    length_unit = f.create_entity("IfcSIUnit", UnitType="LENGTHUNIT", Name="METRE")
    units = f.create_entity("IfcUnitAssignment", Units=[length_unit])
    origin = f.create_entity("IfcCartesianPoint", Coordinates=(0.0, 0.0, 0.0))
    axis = f.create_entity("IfcDirection", DirectionRatios=(0.0, 0.0, 1.0))
    refdir = f.create_entity("IfcDirection", DirectionRatios=(1.0, 0.0, 0.0))
    world = f.create_entity(
        "IfcAxis2Placement3D", Location=origin, Axis=axis, RefDirection=refdir
    )
    ctx = f.create_entity(
        "IfcGeometricRepresentationContext",
        ContextType="Model",
        CoordinateSpaceDimension=3,
        Precision=1e-5,
        WorldCoordinateSystem=world,
    )
    f.create_entity(
        "IfcProject",
        GlobalId=new_guid(),
        OwnerHistory=owner,
        Name="Synthetic Plant Stub",
        RepresentationContexts=[ctx],
        UnitsInContext=units,
    )

    def placement(x: float, y: float, z: float):
        loc = f.create_entity("IfcCartesianPoint", Coordinates=(x, y, z))
        a2p = f.create_entity("IfcAxis2Placement3D", Location=loc)
        return f.create_entity("IfcLocalPlacement", RelativePlacement=a2p)

    def box_rep(dx: float, dy: float, dz: float):
        """A simple extruded rectangle solid so the element has real geometry."""
        prof_pos = f.create_entity(
            "IfcAxis2Placement2D",
            Location=f.create_entity("IfcCartesianPoint", Coordinates=(0.0, 0.0)),
        )
        profile = f.create_entity(
            "IfcRectangleProfileDef",
            ProfileType="AREA",
            Position=prof_pos,
            XDim=dx,
            YDim=dy,
        )
        extrude = f.create_entity(
            "IfcExtrudedAreaSolid",
            SweptArea=profile,
            Position=world,
            ExtrudedDirection=f.create_entity(
                "IfcDirection", DirectionRatios=(0.0, 0.0, 1.0)
            ),
            Depth=dz,
        )
        shape = f.create_entity(
            "IfcShapeRepresentation",
            ContextOfItems=ctx,
            RepresentationIdentifier="Body",
            RepresentationType="SweptSolid",
            Items=[extrude],
        )
        return f.create_entity(
            "IfcProductDefinitionShape", Representations=[shape]
        )

    def add_pset(product, name: str, props: dict):
        hp = [
            f.create_entity(
                "IfcPropertySingleValue",
                Name=k,
                NominalValue=f.create_entity("IfcText", wrappedValue=str(v)),
            )
            for k, v in props.items()
        ]
        pset = f.create_entity(
            "IfcPropertySet",
            GlobalId=new_guid(),
            OwnerHistory=owner,
            Name=name,
            HasProperties=hp,
        )
        f.create_entity(
            "IfcRelDefinesByProperties",
            GlobalId=new_guid(),
            OwnerHistory=owner,
            RelatedObjects=[product],
            RelatingPropertyDefinition=pset,
        )

    # --- IfcTank ---------------------------------------------------------
    tank_guid = new_guid()
    tank = f.create_entity(
        "IfcTank",
        GlobalId=tank_guid,
        OwnerHistory=owner,
        Name="TK-101 Buffer Tank",
        ObjectPlacement=placement(0.0, 0.0, 0.0),
        Representation=box_rep(2.0, 2.0, 4.0),
    )
    add_pset(
        tank,
        "Pset_TankCommon",
        {"Reference": "TK-101", "NominalCapacity": "5000 L", "Service": "buffer"},
    )

    # --- IfcPump ---------------------------------------------------------
    pump_guid = new_guid()
    pump = f.create_entity(
        "IfcPump",
        GlobalId=pump_guid,
        OwnerHistory=owner,
        Name="P-101 Feed Pump",
        ObjectPlacement=placement(4.0, 0.0, 0.0),
        Representation=box_rep(1.0, 0.6, 0.8),
    )
    add_pset(
        pump,
        "Pset_PumpCommon",
        {"Reference": "P-101", "NominalFlowRate": "12 m3/h", "Service": "feed"},
    )

    f.write(out)
    print(f"WROTE {out}")
    print(f"TANK_GUID={tank_guid}")
    print(f"PUMP_GUID={pump_guid}")


if __name__ == "__main__":
    main()

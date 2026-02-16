from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.models.shoe_schemas import ShoeCreateRequest, ShoeUpdateRequest, ShoeResponse
from app.services.auth_service import get_current_user
from app.services import shoe_service

router = APIRouter(prefix="/api/shoes", tags=["shoes"])


@router.get("", response_model=list[ShoeResponse])
async def list_shoes(
    include_retired: bool = Query(False),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    shoes = await shoe_service.get_user_shoes(db, current_user.id, include_retired)
    return [ShoeResponse.model_validate(s) for s in shoes]


@router.post("", response_model=ShoeResponse, status_code=201)
async def create_shoe(
    body: ShoeCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    shoe = await shoe_service.create_shoe(
        db, current_user.id, body.name, body.is_default
    )
    return ShoeResponse.model_validate(shoe)


@router.put("/{shoe_id}", response_model=ShoeResponse)
async def update_shoe(
    shoe_id: str,
    body: ShoeUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    import uuid as _uuid

    shoe = await shoe_service.get_shoe(db, _uuid.UUID(shoe_id), current_user.id)
    if not shoe:
        raise HTTPException(status_code=404, detail="Shoe not found")

    shoe = await shoe_service.update_shoe(
        db, shoe, current_user.id,
        name=body.name,
        is_default=body.is_default,
        is_retired=body.is_retired,
    )
    return ShoeResponse.model_validate(shoe)


@router.delete("/{shoe_id}", status_code=204)
async def delete_shoe(
    shoe_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    import uuid as _uuid

    shoe = await shoe_service.get_shoe(db, _uuid.UUID(shoe_id), current_user.id)
    if not shoe:
        raise HTTPException(status_code=404, detail="Shoe not found")

    await shoe_service.delete_shoe(db, shoe)


@router.post("/{shoe_id}/photo", response_model=ShoeResponse)
async def upload_shoe_photo(
    shoe_id: str,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    import uuid as _uuid

    shoe = await shoe_service.get_shoe(db, _uuid.UUID(shoe_id), current_user.id)
    if not shoe:
        raise HTTPException(status_code=404, detail="Shoe not found")

    file_bytes = await file.read()
    shoe = await shoe_service.upload_shoe_photo(
        db, shoe, file_bytes, file.filename or "shoe.jpg", file.content_type or "image/jpeg"
    )
    return ShoeResponse.model_validate(shoe)

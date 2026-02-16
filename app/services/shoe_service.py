import uuid
from typing import Optional

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.shoe import Shoe
from app.services.storage_service import delete_file


async def create_shoe(
    db: AsyncSession,
    user_id: uuid.UUID,
    name: str,
    is_default: bool = False,
) -> Shoe:
    if is_default:
        await _clear_defaults(db, user_id)

    shoe = Shoe(
        user_id=user_id,
        name=name,
        is_default=is_default,
    )
    db.add(shoe)
    await db.commit()
    await db.refresh(shoe)
    return shoe


async def get_user_shoes(
    db: AsyncSession,
    user_id: uuid.UUID,
    include_retired: bool = False,
) -> list[Shoe]:
    query = select(Shoe).where(Shoe.user_id == user_id)
    if not include_retired:
        query = query.where(Shoe.is_retired == False)
    query = query.order_by(Shoe.created_at.desc())
    result = await db.execute(query)
    return list(result.scalars().all())


async def get_shoe(
    db: AsyncSession,
    shoe_id: uuid.UUID,
    user_id: uuid.UUID,
) -> Optional[Shoe]:
    result = await db.execute(
        select(Shoe).where(Shoe.id == shoe_id, Shoe.user_id == user_id)
    )
    return result.scalar_one_or_none()


async def update_shoe(
    db: AsyncSession,
    shoe: Shoe,
    user_id: uuid.UUID,
    name: Optional[str] = None,
    is_default: Optional[bool] = None,
    is_retired: Optional[bool] = None,
) -> Shoe:
    if is_default is True:
        await _clear_defaults(db, user_id)

    if name is not None:
        shoe.name = name
    if is_default is not None:
        shoe.is_default = is_default
    if is_retired is not None:
        shoe.is_retired = is_retired

    await db.commit()
    await db.refresh(shoe)
    return shoe


async def delete_shoe(db: AsyncSession, shoe: Shoe) -> None:
    if shoe.photo_url:
        try:
            delete_file(shoe.photo_url)
        except Exception:
            pass
    await db.delete(shoe)
    await db.commit()


async def upload_shoe_photo(
    db: AsyncSession,
    shoe: Shoe,
    file_bytes: bytes,
    filename: str,
    content_type: str,
) -> Shoe:
    from app.services.storage_service import upload_file

    # Delete old photo if replacing
    if shoe.photo_url:
        try:
            delete_file(shoe.photo_url)
        except Exception:
            pass

    url = upload_file(file_bytes, filename, content_type, folder="shoes")
    shoe.photo_url = url
    await db.commit()
    await db.refresh(shoe)
    return shoe


async def add_mileage(
    db: AsyncSession,
    shoe_id: uuid.UUID,
    user_id: uuid.UUID,
    distance_km: float,
) -> None:
    await db.execute(
        update(Shoe)
        .where(Shoe.id == shoe_id, Shoe.user_id == user_id)
        .values(total_distance_km=Shoe.total_distance_km + distance_km)
    )


async def _clear_defaults(db: AsyncSession, user_id: uuid.UUID) -> None:
    await db.execute(
        update(Shoe)
        .where(Shoe.user_id == user_id, Shoe.is_default == True)
        .values(is_default=False)
    )

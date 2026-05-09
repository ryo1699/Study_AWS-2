from fastapi import Depends, FastAPI, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from .database import Base, engine, get_db
from .models import Task, TaskStatus
from .schemas import ErrorResponse, TaskInput, TaskResponse

app = FastAPI(title="Task Management API", version="1.0.0")


@app.on_event("startup")
def startup() -> None:
    # Local practice helper. In AWS, run migrations from the bastion instead.
    Base.metadata.create_all(bind=engine)


def to_response(task: Task) -> TaskResponse:
    return TaskResponse(
        id=task.id,
        title=task.title,
        description=task.description,
        status=TaskStatus(task.status),
        createdAt=task.created_at,
        updatedAt=task.updated_at,
    )


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/tasks", response_model=list[TaskResponse])
def list_tasks(status: TaskStatus | None = None, db: Session = Depends(get_db)) -> list[TaskResponse]:
    stmt = select(Task)
    if status is not None:
        stmt = stmt.where(Task.status == status.value)
    tasks = db.scalars(stmt.order_by(Task.id)).all()
    return [to_response(task) for task in tasks]


@app.post("/api/tasks", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
def create_task(payload: TaskInput, db: Session = Depends(get_db)) -> TaskResponse:
    task = Task(title=payload.title, description=payload.description, status=payload.status.value)
    db.add(task)
    db.commit()
    db.refresh(task)
    return to_response(task)


@app.get("/api/tasks/{task_id}", response_model=TaskResponse, responses={404: {"model": ErrorResponse}})
def get_task(task_id: int, db: Session = Depends(get_db)) -> TaskResponse:
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="タスクが見つかりません")
    return to_response(task)


@app.put("/api/tasks/{task_id}", response_model=TaskResponse, responses={404: {"model": ErrorResponse}})
def update_task(task_id: int, payload: TaskInput, db: Session = Depends(get_db)) -> TaskResponse:
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="タスクが見つかりません")

    task.title = payload.title
    task.description = payload.description
    task.status = payload.status.value
    db.commit()
    db.refresh(task)
    return to_response(task)


@app.delete("/api/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT, responses={404: {"model": ErrorResponse}})
def delete_task(task_id: int, db: Session = Depends(get_db)) -> Response:
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="タスクが見つかりません")

    db.delete(task)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

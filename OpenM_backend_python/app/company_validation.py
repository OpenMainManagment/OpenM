"""
Organization validation utilities for multi-tenant data isolation.

Provides reusable functions to validate organization context, access control,
and data isolation across the application.
"""

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from .models import Organization, Employee


def validate_company_exists(company_id: str, db: Session) -> Organization:
    """
    Validate that an organization exists and return it.
    
    Args:
        company_id: UUID of the organization to validate
        db: Database session
        
    Returns:
        Organization object if valid
        
    Raises:
        HTTPException with 404 status if organization not found
    """
    organization = db.get(Organization, company_id)
    if organization is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Organization '{company_id}' not found"
        )
    return organization


def validate_employee_company_access(
    employee_id: str,
    company_id: str,
    db: Session
) -> bool:
    """
    Validate that an employee belongs to a specific company.
    
    Args:
        employee_id: UUID of the employee
        company_id: UUID of the company to check
        db: Database session
        
    Returns:
        True if employee belongs to the company
        
    Raises:
        HTTPException with 403 status if no access
    """
    employee = db.get(Employee, employee_id)
    if employee is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Employee not found"
        )
    
    if employee.organization_id != company_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied: You don't have access to this organization"
        )
    
    return True


def verify_company_data_isolation(
    user_company_id: str | None,
    resource_company_id: str | None
) -> bool:
    """
    Verify that user and resource belong to the same company.
    
    This prevents cross-company data access in multi-tenant scenarios.
    
    Args:
        user_company_id: Company ID from user's JWT token
        resource_company_id: Company ID of the resource being accessed
        
    Returns:
        True if both are in the same company
        
    Raises:
        HTTPException with 403 status if companies don't match
    """
    if user_company_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User company context is missing"
        )
    
    if resource_company_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Resource company context is missing"
        )
    
    if user_company_id != resource_company_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied: Cannot access resources from another company"
        )
    
    return True


def get_employee_company_id(
    current_employee: Employee,
    db: Session | None = None
) -> str:
    """
    Extract company_id from an employee object.
    
    Args:
        current_employee: Employee object from get_current_employee
        db: Optional database session (for future enhancements)
        
    Returns:
        Company ID string
        
    Raises:
        HTTPException with 400 status if employee has no company assignment
    """
    if current_employee.organization_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Your account is not assigned to any organization. Please contact your administrator."
        )
    
    return current_employee.organization_id

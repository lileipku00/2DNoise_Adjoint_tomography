!========================================================================
!
!                   S P E C F E M 2 D  Version 7 . 0
!                   --------------------------------
!
!     Main historical authors: Dimitri Komatitsch and Jeroen Tromp
!                        Princeton University, USA
!                and CNRS / University of Marseille, France
!                 (there are currently many more authors!)
! (c) Princeton University and CNRS / University of Marseille, April 2014
!
! This software is a computer program whose purpose is to solve
! the two-dimensional viscoelastic anisotropic or poroelastic wave equation
! using a spectral-element method (SEM).
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 2 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
!
! The full text of the license is available in file "LICENSE".
!
!========================================================================

  subroutine compute_forces_acoustic_GPU()

  use specfem_par, only: NPROC,ninterface,max_nibool_interfaces_ext_mesh,nibool_interfaces_ext_mesh, &
    my_neighbours,ninterface_acoustic,inum_interfaces_acoustic, &
    nelem_acoustic_surface,num_fluid_solid_edges, &
    STACEY_ABSORBING_CONDITIONS,any_elastic,any_poroelastic,SIMULATION_TYPE

  use specfem_par, only: nspec_outer_acoustic, nspec_inner_acoustic

  use specfem_par_gpu, only: Mesh_pointer,deltatover2f,b_deltatover2f, &
    buffer_send_scalar_gpu,buffer_recv_scalar_gpu, &
    b_buffer_send_scalar_gpu,b_buffer_recv_scalar_gpu, &
    request_send_recv_scalar_gpu,b_request_send_recv_scalar_gpu

  implicit none

  ! local parameters
  integer:: iphase

  if (nelem_acoustic_surface > 0) then
    !  enforces free surface (zeroes potentials at free surface)
    call acoustic_enforce_free_surf_cuda(Mesh_pointer)
  endif

  ! distinguishes two runs: for elements on MPI interfaces, and elements within the partitions
  do iphase = 1,2

    ! acoustic pressure term
    ! includes code for SIMULATION_TYPE==3
    call compute_forces_acoustic_cuda(Mesh_pointer, iphase, &
                                      nspec_outer_acoustic, nspec_inner_acoustic)

    ! computes additional contributions
    if (iphase == 1) then
      ! Stacey absorbing boundary conditions
      if (STACEY_ABSORBING_CONDITIONS) then
        call compute_stacey_acoustic_GPU(iphase)
      endif

      ! elastic coupling
      if (any_elastic) then
        if (num_fluid_solid_edges > 0) then
          ! on GPU
          call compute_coupling_ac_el_cuda(Mesh_pointer,iphase, &
                                           num_fluid_solid_edges)
        endif
      endif

      ! poroelastic coupling
      if (any_poroelastic) then
            stop 'poroelastic not implemented yet in GPU mode'
      endif

      ! sources
      call compute_add_sources_acoustic_GPU(iphase)
    endif

    ! assemble all the contributions between slices using MPI
    if (ninterface_acoustic > 0) then

      if (iphase == 1) then
        ! sends potential_dot_dot_acoustic values to corresponding MPI interface neighbors (non-blocking)
        call transfer_boun_pot_from_device(Mesh_pointer, &
                                           buffer_send_scalar_gpu, &
                                           1) ! -- 1 == fwd accel

        call assemble_MPI_scalar_send_cuda(NPROC, &
                          buffer_send_scalar_gpu,buffer_recv_scalar_gpu, &
                          ninterface,max_nibool_interfaces_ext_mesh, &
                          nibool_interfaces_ext_mesh, &
                          my_neighbours, &
                          request_send_recv_scalar_gpu,ninterface_acoustic,inum_interfaces_acoustic)

        ! adjoint simulations
        if (SIMULATION_TYPE == 3) then
          call transfer_boun_pot_from_device(Mesh_pointer, &
                                             b_buffer_send_scalar_gpu, &
                                             3) ! -- 3 == adjoint b_accel

          call assemble_MPI_scalar_send_cuda(NPROC, &
                            b_buffer_send_scalar_gpu,b_buffer_recv_scalar_gpu, &
                            ninterface,max_nibool_interfaces_ext_mesh, &
                            nibool_interfaces_ext_mesh, &
                            my_neighbours, &
                            b_request_send_recv_scalar_gpu,ninterface_acoustic,inum_interfaces_acoustic)
        endif

      else
        ! waits for send/receive requests to be completed and assembles values
        call assemble_MPI_scalar_write_cuda(NPROC, &
                          Mesh_pointer, &
                          buffer_recv_scalar_gpu, &
                          ninterface, &
                          max_nibool_interfaces_ext_mesh, &
                          request_send_recv_scalar_gpu, &
                          1,ninterface_acoustic,inum_interfaces_acoustic)



        ! adjoint simulations
        if (SIMULATION_TYPE == 3) then
          call assemble_MPI_scalar_write_cuda(NPROC, &
                          Mesh_pointer, &
                          b_buffer_recv_scalar_gpu, &
                          ninterface, &
                          max_nibool_interfaces_ext_mesh, &
                          b_request_send_recv_scalar_gpu, &
                          3,ninterface_acoustic,inum_interfaces_acoustic)
        endif
      endif

    endif !interface_acoustic


  enddo


  ! divides pressure with mass matrix
  ! corrector:
  ! updates the chi_dot term which requires chi_dot_dot(t+delta)
  call kernel_3_acoustic_cuda(Mesh_pointer,deltatover2f,b_deltatover2f)

  ! enforces free surface (zeroes potentials at free surface)
  call acoustic_enforce_free_surf_cuda(Mesh_pointer)

  end subroutine compute_forces_acoustic_GPU

!
!---------------------------------------------------------------------------------------------
!

! for acoustic solver on GPU

  subroutine compute_stacey_acoustic_GPU(iphase)

  use constants, only: CUSTOM_REAL,NGLLX

  use specfem_par, only: nspec_bottom,nspec_left,nspec_top,nspec_right,b_absorb_acoustic_left,b_absorb_acoustic_right, &
                          b_absorb_acoustic_bottom, b_absorb_acoustic_top,it,NSTEP,SIMULATION_TYPE,SAVE_FORWARD, &
                          nelemabs

  use specfem_par_gpu, only: Mesh_pointer

  implicit none

  ! communication overlap
  integer,intent(in) :: iphase

  ! adjoint simulations
  real(kind=CUSTOM_REAL),dimension(NGLLX,nspec_bottom) :: b_absorb_potential_bottom_slice
  real(kind=CUSTOM_REAL),dimension(NGLLX,nspec_left) :: b_absorb_potential_left_slice
  real(kind=CUSTOM_REAL),dimension(NGLLX,nspec_right) :: b_absorb_potential_right_slice
  real(kind=CUSTOM_REAL),dimension(NGLLX,nspec_top) :: b_absorb_potential_top_slice

  ! checks if anything to do
  if (nelemabs == 0) return

  if (SIMULATION_TYPE == 3) then
    ! gets absorbing contributions buffers
    b_absorb_potential_left_slice(:,:) = b_absorb_acoustic_left(:,:,NSTEP-it+1)
    b_absorb_potential_right_slice(:,:) = b_absorb_acoustic_right(:,:,NSTEP-it+1)
    b_absorb_potential_top_slice(:,:) = b_absorb_acoustic_top(:,:,NSTEP-it+1)
    b_absorb_potential_bottom_slice(:,:) = b_absorb_acoustic_bottom(:,:,NSTEP-it+1)
  endif

  ! absorbs absorbing-boundary surface using Sommerfeld condition (vanishing field in the outer-space)
  call compute_stacey_acoustic_cuda(Mesh_pointer,iphase,b_absorb_potential_left_slice,b_absorb_potential_right_slice, &
                                     b_absorb_potential_top_slice,b_absorb_potential_bottom_slice)

  ! adjoint simulations: stores absorbed wavefield part
  if (SIMULATION_TYPE == 1 .and. SAVE_FORWARD) then
    ! writes out absorbing boundary value only when second phase is running
    b_absorb_acoustic_bottom(:,:,it) = b_absorb_potential_bottom_slice(:,:)
    b_absorb_acoustic_right(:,:,it) = b_absorb_potential_right_slice(:,:)
    b_absorb_acoustic_top(:,:,it) = b_absorb_potential_top_slice(:,:)
    b_absorb_acoustic_left(:,:,it) = b_absorb_potential_left_slice(:,:)
  endif

  end subroutine compute_stacey_acoustic_GPU

!
!---------------------------------------------------------------------------------------------
!

  subroutine compute_add_sources_acoustic_GPU(iphase)

  use specfem_par, only: it,SIMULATION_TYPE,NSTEP, nadj_rec_local

  use specfem_par_gpu, only: Mesh_pointer

  implicit none

  ! communication overlap
  integer,intent(in) :: iphase

  ! forward simulations
  if (SIMULATION_TYPE == 1) call compute_add_sources_ac_cuda(Mesh_pointer,iphase,it)

  ! adjoint simulations
  if (SIMULATION_TYPE == 3 .and. nadj_rec_local > 0 .and. it < NSTEP) then
    call add_sources_ac_sim_2_or_3_cuda(Mesh_pointer,iphase, NSTEP -it + 1, nadj_rec_local,NSTEP)
  endif

  ! adjoint simulations
  if (SIMULATION_TYPE == 3) call compute_add_sources_ac_s3_cuda(Mesh_pointer,iphase,NSTEP -it + 1)

  end subroutine compute_add_sources_acoustic_GPU

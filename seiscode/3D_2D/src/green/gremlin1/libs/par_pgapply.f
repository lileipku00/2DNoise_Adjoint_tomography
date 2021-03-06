c this is <par_pgapply.f>
c------------------------------------------------------------------------------
cS
c $Id$
c
c Copyright 1999, 2010 by Thomas Forbriger (IfG Stuttgart)
c
c apply pgplot parameters
c
c ----
c This program is free software; you can redistribute it and/or modify
c it under the terms of the GNU General Public License as published by
c the Free Software Foundation; either version 2 of the License, or
c (at your option) any later version. 
c 
c This program is distributed in the hope that it will be useful,
c but WITHOUT ANY WARRANTY; without even the implied warranty of
c MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
c GNU General Public License for more details.
c 
c You should have received a copy of the GNU General Public License
c along with this program; if not, write to the Free Software
c Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
c ----
c
c REVISIONS and CHANGES
c    20/01/99   V1.0   Thomas Forbriger
c    02/03/99   V1.1   set background colour too
c
c==============================================================================
c
      subroutine par_pgapply
c
      include 'glq_pgpara.inc'
c
cE
      integer i
c
      call pgslw(pg_lw)
      call pgsch(pg_ch)
      call pgsci(pg_colind)
      do i=0,pg_maxrgb
        call pgscr(i,pg_rgbtable(1,i),pg_rgbtable(2,i),pg_rgbtable(3,i))
      enddo
c
      return
      end
c
c ----- END OF par_pgapply.f -----

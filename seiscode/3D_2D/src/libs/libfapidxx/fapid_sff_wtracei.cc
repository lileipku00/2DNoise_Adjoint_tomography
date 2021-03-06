/*! \file fapid_sff_wtracei.cc
 * \brief mimic sff_WTraceI function - write a trace with INFO line (implementation)
 * 
 * ----------------------------------------------------------------------------
 * 
 * \author Thomas Forbriger
 * \date 23/12/2010
 * 
 * mimic sff_WTraceI function - write a trace with INFO line (implementation)
 * 
 * Copyright (c) 2010 by Thomas Forbriger (BFO Schiltach) 
 *
 * ----
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version. 
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 * ----
 * 
 * REVISIONS and CHANGES 
 *  - 23/12/2010   V1.0   Thomas Forbriger
 * 
 * ============================================================================
 */
#define TF_FAPID_SFF_WTRACEI_CC_VERSION \
  "TF_FAPID_SFF_WTRACEI_CC   V1.0   "

#include <fapidxx/fapidsff.h>
#include <fapidxx/fileunit.h>
#include <fapidxx/helper.h>
#include <fapidxx/wid2container.h>
#include <fapidxx/error.h>

using namespace fapidxx;

/*! \brief Write one trace of data with INFO line
 *
 * \ingroup implemented_functions
 *
 * Description from stuff.f:
 * \code
c----------------------------------------------------------------------
      subroutine sff_WTraceI(lu, 
     &                   wid2line, nsamp, fdata, idata, last, 
     &                   cs, c1, c2, c3, nstack, ierr)
c
c Write one data block starting with DAST line.
c Write also  INFO line.
c The File will be closed after writing the last trace.
c 
c input
c   lu              logical file unit
c   wid2line        valid WID2 line
c   nsamp           number of samples
c   fdata           data array
c   last            must be true is the trace to be written is the
c                   last one in this file
c   cs              coordinate system
c   c1, c2, c3      receiver coordinates
c   nstack          number of stacks
c ouput:
c   ierr            error status (ok: ierr=0)
c
c workspace:
c   idata           fdata will be converted to idata using sff_f2i
c                   (both array may be in same memory space - see
c                   comments on sff_f2i)
c
c----------------------------------------------------------------------
 * \endcode
 */
int sff_wtracei__(integer *lu, char *wid2line, integer *nsamp, real *fdata,
                  integer *idata, logical *last, char *cs, real *c1, real *c2,
                  real *c3, integer *nstack, integer *ierr, ftnlen
                  wid2line_len, ftnlen cs_len)
{
  int retval=0;
  *ierr=0;
  try {
    datrw::oanystream &os=ostreammanager(static_cast<int>(*lu));
    WID2container wid2c(wid2line, wid2line_len);
    unsigned int nsamples=static_cast<unsigned int>(*nsamp);
    os << wid2c.wid2;
    if (os.handlesinfo())
    {
      sff::INFO info;
      info.cs=sff::coosysID(*cs);
      info.cx=static_cast<double>(*c1);
      info.cy=static_cast<double>(*c2);
      info.cz=static_cast<double>(*c3);
      info.nstacks=static_cast<int>(*nstack);
      os << info;
    }
    aff::LinearShape shape(0, nsamples-1, 0);
    datrw::Tfseries series(shape, aff::SharedHeap<real>(fdata, *nsamp));
    os << series;
    if (*last) ostreammanager.close(static_cast<int>(*lu));
  }
  catch (...) {
    *ierr=1;
  }
  return(retval);
} // int sff_wtracei__

/* ----- END OF fapid_sff_wtracei.cc ----- */

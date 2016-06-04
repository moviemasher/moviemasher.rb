
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
  context 'spec_process_job_files' do
    it 'correctly renders mash text transition' do
      spec_process_job_files 'mash_trans'
    end
    it 'correctly renders mash transition' do
      spec_process_job_files 'mash_transition'
    end
    it 'correctly renders mash text' do
      spec_process_job_files 'mash_text'
    end
    it 'correctly renders mash theme effect' do
      spec_process_job_files 'mash_theme_effect'
    end
    it 'correctly renders mash pan' do
      spec_process_job_files 'mash_pan_overlay'
    end
    it 'correctly renders mash color' do
      spec_process_job_files 'mash_color'
    end
    it 'correctly renders color to jpg' do
      spec_process_job_files 'mash_color', 'image-16x9-md-jpg'
    end
    it 'correctly renders mash overlays' do
      spec_process_job_files 'mash_overlays'
    end
    it 'correctly renders mash fill' do
      spec_process_job_files 'mash_fill'
    end
    it 'correctly renders mash color video' do
      spec_process_job_files 'mash_color_video'
    end
  end
end

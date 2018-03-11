require "rails_helper"

RSpec.describe AssetsController, type: :controller do
  render_views
  fixtures :assets, :users
  include ActiveJob::TestHelper

  context "#latest" do
    it "should render the home page" do
      get :latest
      expect(response).to be_successful
    end

    it "should render the home page (white)" do
      get :latest, params: { white: true }
      expect(response).to be_successful
    end
  end

  context "show" do
    it "should render without errors" do
      get :show, params: {id: 'song1', user_id: users(:sudara).login }
      expect(response).to be_successful
    end

    it "should render without errors (white)" do
      get :show, params: {id: 'song1', user_id: users(:sudara).login, white: true}
      expect(response).to be_successful
    end
  end

  context "#show.mp3" do
    subject do
      request.headers["HTTP_ACCEPT"] = "audio/mpeg"
      get :show, params: { id: 'song1', user_id: users(:sudara).login, format: :mp3 }
    end

    GOOD_USER_AGENTS = [
      "Mozilla/5.0 (Macintosh; U; Intel Mac OS X; en) AppleWebKit/XX (KHTML, like Gecko) Safari/YY",
      "Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8) Gecko/20060319 Firefox/2.0",
      "iTunes/x.x.x",
      "Mozilla/4.0 (compatible; MSIE 7.0b; Windows NT 6.0)",
      "msie",
      'webkit'
    ]

    BAD_USER_AGENTS = [
      "Mp3Bot/0.1 (http://mp3realm.org/mp3bot/)",
      "",
      "Googlebot/2.1 (+http://www.google.com/bot.html)",
      "you're momma's so bot...",
      "Baiduspider+(+http://www.baidu.jp/spider/)",
      "baidu/Nutch-1.0 "
    ]

    GOOD_USER_AGENTS.each do |agent|
      it "should register a listen for #{agent}" do
        request.headers["User-Agent"] = agent
        expect{ subject }.to change{ Listen.count }.by(1)
      end
    end

    BAD_USER_AGENTS.each do |agent|
      it "should not register a listen for #{agent}" do
        request.user_agent = agent
        expect{ subject }.not_to change{ Listen.count }
      end
    end

    it "should NOT register more than one listen from one ip/track in short amount of time" do
      request.user_agent = GOOD_USER_AGENTS.first
      expect do
        request.env["HTTP_ACCEPT"] = "audio/mpeg"
        get :show, :params => {:id => 'song1', :user_id => users(:sudara).login, :format => :mp3}
        get :show, :params => {:id => 'song1', :user_id => users(:sudara).login, :format => :mp3}
        get :show, :params => {:id => 'song1', :user_id => users(:sudara).login, :format => :mp3}
      end.to change{ Listen.count }.by(1)
    end

    it "should register mulitple listens when they are spaced" do
      request.user_agent = GOOD_USER_AGENTS.first
      expect do
        request.headers["HTTP_ACCEPT"] = "audio/mpeg"
        travel_to(3.hours.ago) do
          get :show, :params => {:id => 'song1', :user_id => users(:sudara).login, :format => :mp3}
        end
        travel_to(2.hours.ago) do
          get :show, :params => {:id => 'song1', :user_id => users(:sudara).login, :format => :mp3}
        end
        travel_to(1.hour.ago) do
          get :show, :params => {:id => 'song1', :user_id => users(:sudara).login, :format => :mp3}
        end
      end.to change{ Listen.count }.by(3)
    end

    it 'should accept a mp3 extension and redirect to the amazon url' do
      request.env["HTTP_ACCEPT"] = "audio/mpeg"
      request.user_agent = GOOD_USER_AGENTS.first
      subject
      # expect(response).to redirect_to(assets(:valid_mp3).mp3.url) # on s3, we get a redirect
      expect(response.response_code).to eq(200) # in test mode, we get a file
    end

    it 'should have a landing page' do
      request.user_agent = GOOD_USER_AGENTS.first
      get :show, :params => {:id => 'song1', :user_id => users(:sudara).login}
      expect(assigns(:assets)).to be_present
      expect(response.response_code).to eq(200)
    end

    it 'should properly detect leeching blacklisted sites and not register a listen' do
      request.user_agent = 'mp3bot'
      expect{ subject }.not_to change(Listen, :count)
      expect(response.response_code).to eq(403)
    end

    it 'should consider an empty user agent to be a spider and not register a listen' do
      request.user_agent = ''
      expect{ subject }.not_to change(Listen, :count)
    end

    it 'should consider any user agent with BOT in its string a bot and not register a listen' do
      request.user_agent = 'bot'
      expect{ subject }.not_to change(Listen, :count)
    end

    it 'should record the refferer' do
      request.user_agent = GOOD_USER_AGENTS.first
      request.env["HTTP_REFERER"] = "https://alonetone.com/blah/blah"
      expect{ subject }.to change(Listen, :count)
      expect(Listen.last.source).to eq("https://alonetone.com/blah/blah")
    end

    it 'should allow the refferer to be manually overridden by params' do
      request.env["HTTP_REFERER"] = "https://alonetone.com/blah/blah"
      request.user_agent = GOOD_USER_AGENTS.first
      expect{ get :show, :params => {:id => 'song1', :user_id => users(:arthur).login, :format => :mp3, :referer => 'itunes' }}.to change(Listen, :count)
      expect(Listen.last.source).to eq('itunes')
    end

    it 'should say "direct hit" when no referer' do
      request.env["HTTP_REFERER"] = nil
      request.user_agent = GOOD_USER_AGENTS.first
      expect{ subject }.to change(Listen, :count)
      expect(Listen.last.source).to eq("direct hit")
    end
  end

  context '#create' do
    subject do
      login(:sudara)
      post :create, params: { user_id: users(:sudara).login, asset_data: [fixture_file_upload('assets/muppets.mp3','audio/mpeg')] }
    end

    it 'should successfully upload an mp3' do
      expect { subject }.to change{ Asset.count }.by(1)
      expect(flash[:error]).not_to be_present
      expect(response).to redirect_to('http://test.host/sudara/tracks/mass_edit?assets%5B%5D='+Asset.last.id.to_s)
    end


    it 'should accept an uploaded mp3 from chrome' do
      login(:sudara)
      post :create, params: { user_id: users(:sudara).login, asset_data: [fixture_file_upload('assets/muppets.mp3','audio/mp3')] }
      expect(flash[:error]).not_to be_present
      expect(response).to redirect_to('http://test.host/sudara/tracks/mass_edit?assets%5B%5D='+Asset.last.id.to_s)
    end

    it "should email followers and generate waveform via queue" do
      users(:arthur).add_or_remove_followee(users(:sudara).id)
      subject
      expect(enqueued_jobs.size).to eq 2
      expect(enqueued_jobs.first[:queue]).to eq "mailers"
    end

    it 'should successfully upload 2 mp3s' do
      login(:sudara)
      post :create, params: { user_id: users(:sudara).login, asset_data: [fixture_file_upload('assets/muppets.mp3','audio/mpeg'),
                                                                      fixture_file_upload('assets/muppets.mp3','audio/mpeg')] }
      expect(flash[:error]).not_to be_present
      expect(response).to redirect_to('http://test.host/sudara/tracks/mass_edit?assets%5B%5D='+Asset.last(2).first.id.to_s + '&assets%5B%5D=' + Asset.last.id.to_s )
    end

    it "should successfully extract mp3s from a zip" do
      login(:sudara)
      post :create, params: { user_id: users(:sudara).login, asset_data: [fixture_file_upload('assets/1valid-1invalid.zip','application/zip')] }
      expect(flash[:error]).not_to be_present
    end

    it "should allow an mp3 upload from an url" do
      login(:sudara)
      post :create, params: { user_id: users(:sudara).login, asset_data: ["https://github.com/sudara/alonetone/raw/master/spec/fixtures/assets/muppets.mp3"] }
      expect(flash[:error]).not_to be_present
    end

    it "should allow a zip upload from an url" do
      login(:sudara)
      post :create, params: { user_id: users(:sudara).login, asset_data: ["https://github.com/sudara/alonetone/raw/master/spec/fixtures/assets/1valid-1invalid.zip"] }
      expect(flash[:error]).not_to be_present
    end

  end

  context "edit" do
    it 'should allow user to upload new version of song' do
      login(:sudara)
      post :create, params: { user_id: users(:sudara).login, asset_data: [fixture_file_upload('assets/muppets.mp3','audio/mpeg')] }
      expect(users(:sudara).assets.first.mp3_file_name).to eq('muppets.mp3')
      put :update, :params => {:id => users(:sudara).assets.first, :user_id => users(:sudara).login, :asset => {:mp3 => fixture_file_upload('assets/tag1.mp3','audio/mpeg')}}
      expect(users(:sudara).assets.reload.first.mp3_file_name).to eq('tag1.mp3')
    end
  end

  context "#mass_edit" do
    it 'should allow user to edit 1 track' do
      login(:arthur)
      get :mass_edit, params: { user_id: users(:arthur).login, assets: [assets(:valid_arthur_mp3).id] }
      expect(response).to be_successful
      expect(assigns(:assets)).to include(assets(:valid_arthur_mp3))
    end

    it 'should allow user to edit 2 tracks at once' do
      login(:sudara)
      two_assets = [users(:sudara).assets.first,  users(:sudara).assets.last]
      get :mass_edit, params: {user_id: users(:sudara).login, assets: two_assets.collect(&:id) }
      expect(response).to be_successful
      expect(assigns(:assets)).to include(two_assets.first)
      expect(assigns(:assets)).to include(two_assets.last)
    end

    it 'should not allow user to edit other peoples tracks' do
      login(:arthur)
      get :mass_edit, params: { user_id: users(:arthur).login, assets: [assets(:valid_mp3).id] }
      expect(response).to be_successful # no wrong answer here :)
      expect(assigns(:assets)).not_to include(assets(:valid_mp3))
      expect(assigns(:assets)).to be_present # should be populated with user's own assets
    end
  end

  context "#update" do
    before do
      login(:arthur)
    end

    it 'should allow user to update track title and description' do
      put :update, params: { id: users(:arthur).assets.first, user_id: users(:arthur).login, asset: {description: 'normal description' }}, xhr: true
      expect(response).to be_successful
    end

    it 'should call out to rakismet on update' do
      allow(Rakismet).to receive(:akismet_call).and_return('false')
      put :update, params: { id: users(:arthur).assets.first, user_id: users(:arthur).login, asset: {description: 'normal description' }}, xhr: true
      expect(users(:arthur).assets.first.private).to be_falsey
    end

    it 'should force a track to be private if it is spam' do
      allow(Rakismet).to receive(:akismet_call).and_return('true')
      put :update, params: { id: users(:arthur).assets.first, user_id: users(:arthur).login, asset: {description: 'spammy description' }}, xhr: true
      expect(assigns(:asset).private).to be_truthy
    end
  end
end
